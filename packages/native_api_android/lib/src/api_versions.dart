import 'package:native_api_ir/native_api_ir.dart';
import 'package:xml/xml_events.dart';

import 'classfile/byte_reader.dart';

/// Availability information for one symbol from `api-versions.xml`.
final class VersionInfo {
  /// Creates version info.
  const VersionInfo({this.since, this.deprecated, this.removed, this.sdks});

  /// Introduced in.
  final ApiVersion? since;

  /// Deprecated in.
  final ApiVersion? deprecated;

  /// Removed in.
  final ApiVersion? removed;

  /// Raw SDK extension list.
  final String? sdks;

  /// Converts to IR availability. `since` is inherited from [owner] when
  /// absent and never earlier than the owner's (a member cannot exist before
  /// its declaring class).
  Availability toAvailability([VersionInfo? owner]) {
    var introduced = since ?? owner?.since ?? const ApiVersion(1);
    final o = owner?.since;
    if (o != null && o > introduced) introduced = o;
    return Availability(
      introduced: introduced,
      deprecated: deprecated,
      removed: removed,
      sdkExtensions: sdks,
    );
  }
}

/// Per-class availability record.
final class ClassVersions {
  ClassVersions._(this.info);

  /// Class availability.
  final VersionInfo info;

  /// Methods keyed by `name + descriptor` (e.g. `<init>()V`).
  final methods = <String, VersionInfo>{};

  /// Fields keyed by name.
  final fields = <String, VersionInfo>{};

  /// Direct supertypes (`extends` + `implements`) as binary names.
  final supertypes = <String>[];
}

/// Index over `platforms/android-N/data/api-versions.xml`: the official list
/// of public SDK symbols with the API level each was introduced in.
final class ApiVersionsIndex {
  ApiVersionsIndex._(this.classes);

  /// Parses the XML text with a streaming parser.
  factory ApiVersionsIndex.parse(String xml) {
    final classes = <String, ClassVersions>{};
    ClassVersions? current;
    try {
      for (final e in parseEvents(xml)) {
        if (e is XmlStartElementEvent) {
          String? attr(String n) {
            for (final a in e.attributes) {
              if (a.name == n) return a.value;
            }
            return null;
          }

          VersionInfo info() => VersionInfo(
            since: ApiVersion.tryParse(attr('since')),
            deprecated: ApiVersion.tryParse(attr('deprecated')),
            removed: ApiVersion.tryParse(attr('removed')),
            sdks: attr('sdks'),
          );

          switch (e.name) {
            case 'class':
              final name = attr('name');
              if (name == null) continue;
              current = ClassVersions._(info());
              classes[name.replaceAll('/', '.')] = current;
              if (e.isSelfClosing) current = null;
            case 'method':
              final name = attr('name');
              if (current != null && name != null) {
                current.methods[name] = info();
              }
            case 'extends' || 'implements':
              final name = attr('name');
              if (current != null && name != null && attr('removed') == null) {
                current.supertypes.add(name.replaceAll('/', '.'));
              }
            case 'field':
              final name = attr('name');
              if (current != null && name != null) {
                current.fields[name] = info();
              }
          }
        } else if (e is XmlEndElementEvent && e.name == 'class') {
          current = null;
        }
      }
    } on Exception catch (e) {
      throw MalformedInputException('api-versions.xml: $e');
    }
    return ApiVersionsIndex._(classes);
  }

  /// Classes by binary name (`android.os.Handler$Callback`).
  final Map<String, ClassVersions> classes;

  /// Looks up a method declared in [owner] or, for overrides that the list
  /// does not repeat, in the nearest listed ancestor. Matching ignores the
  /// return type so covariant overrides resolve. Returns the declaring
  /// record's info with `since` raised to the owner's `since`.
  VersionInfo? method(
    String owner,
    String name,
    String descriptor, {
    Iterable<String> extraSupertypes = const [],
  }) {
    final own = classes[owner];
    if (own == null) return null;
    final direct = own.methods[name + descriptor];
    if (direct != null) return direct;
    if (name == '<init>') return null; // constructors are not inherited
    final params = descriptor.substring(0, descriptor.indexOf(')') + 1);
    final found = _search(owner, extraSupertypes, (c) {
      for (final e in c.methods.entries) {
        if (e.key.startsWith('$name(') &&
            e.key.substring(name.length, e.key.indexOf(')') + 1) == params) {
          return e.value;
        }
      }
      return null;
    });
    return found == null ? null : _inherit(found, own.info);
  }

  /// Looks up a field in [owner] or an ancestor (fields are inherited).
  VersionInfo? field(
    String owner,
    String name, {
    Iterable<String> extraSupertypes = const [],
  }) {
    final own = classes[owner];
    if (own == null) return null;
    final direct = own.fields[name];
    if (direct != null) return direct;
    final found = _search(owner, extraSupertypes, (c) => c.fields[name]);
    return found == null ? null : _inherit(found, own.info);
  }

  VersionInfo _inherit(VersionInfo member, VersionInfo owner) {
    final since =
        member.since == null ||
            (owner.since != null && owner.since! > member.since!)
        ? owner.since
        : member.since;
    return VersionInfo(
      since: since,
      deprecated: member.deprecated,
      removed: member.removed,
      sdks: member.sdks,
    );
  }

  /// [extra] adds supertypes known from the class file; the list omits
  /// interfaces that public stubs implement directly but the platform
  /// implements through non-public intermediates.
  VersionInfo? _search(
    String start,
    Iterable<String> extra,
    VersionInfo? Function(ClassVersions) probe,
  ) {
    final seen = <String>{start};
    final queue = <String>[...?classes[start]?.supertypes, ...extra];
    while (queue.isNotEmpty) {
      final id = queue.removeAt(0);
      if (!seen.add(id)) continue;
      final c = classes[id];
      if (c == null) continue;
      final hit = probe(c);
      if (hit != null) return hit;
      queue.addAll(c.supertypes);
    }
    return null;
  }
}
