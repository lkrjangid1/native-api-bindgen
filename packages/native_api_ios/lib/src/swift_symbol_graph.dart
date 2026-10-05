import 'dart:convert';
import 'dart:io';

import 'package:native_api_ir/native_api_ir.dart';

/// A Swift type as written in a declaration, reduced to what adapter
/// generation needs.
sealed class SwiftType {
  const SwiftType(this.display);

  /// Source text, e.g. `String?`.
  final String display;
}

/// `Void` / `()`.
final class SwiftVoid extends SwiftType {
  /// Creates the void type.
  const SwiftVoid() : super('Void');
}

/// A nominal type (`Int`, `String`, `Counter`), possibly optional.
final class SwiftNamed extends SwiftType {
  /// Creates a nominal type.
  const SwiftNamed(super.display, this.name, this.usr, {this.optional = false});

  /// Simple name.
  final String name;

  /// Precise identifier (USR, e.g. `s:Si`), or null.
  final String? usr;

  /// `T?` / `T!`.
  final bool optional;
}

/// Anything else (closure, tuple, collection, generic, existential, ...).
final class SwiftOther extends SwiftType {
  /// Creates an unsupported type with the [code] and [reason] to report.
  const SwiftOther(super.display, this.code, this.reason);

  /// Diagnostic code.
  final DiagnosticCode code;

  /// Why it cannot be adapted.
  final String reason;
}

/// One parameter.
final class SwiftParam {
  /// Creates a parameter.
  const SwiftParam(this.label, this.name, this.type);

  /// External label, or `_`.
  final String label;

  /// Internal name.
  final String name;

  /// Type.
  final SwiftType type;
}

/// Kind of a Swift member.
enum SwiftMemberKind {
  /// `init(...)`.
  initializer,

  /// Instance method.
  method,

  /// `static`/`class` method.
  typeMethod,

  /// Instance property.
  property,

  /// `static`/`class` property.
  typeProperty,

  /// Operator or other member (not adapted).
  other,
}

/// iOS availability of a declaration (from the symbol graph).
final class SwiftAvailability {
  /// Creates availability.
  const SwiftAvailability({this.introduced, this.unavailable = false});

  /// `introduced` for iOS (e.g. `26.0`), or null.
  final String? introduced;

  /// Unavailable on iOS.
  final bool unavailable;

  /// Parses the `availability` array of a symbol.
  static SwiftAvailability parse(Object? list) {
    String? introduced;
    var unavailable = false;
    for (final a in (list as List?) ?? const []) {
      final m = a as Map<String, Object?>;
      final domain = m['domain'];
      if (domain != 'iOS' && domain != '*') continue;
      if (m['isUnconditionallyUnavailable'] == true) unavailable = true;
      final i = m['introduced'] as Map<String, Object?>?;
      if (i != null && domain == 'iOS') {
        introduced = '${i['major'] ?? 0}.${i['minor'] ?? 0}';
      }
    }
    return SwiftAvailability(introduced: introduced, unavailable: unavailable);
  }
}

/// One public member from the symbol graph.
final class SwiftMember {
  /// Creates a member.
  SwiftMember({
    required this.usr,
    required this.kind,
    required this.title,
    required this.baseName,
    required this.params,
    required this.returnType,
    required this.declaration,
    this.settable = false,
    this.isAsync = false,
    this.throws = false,
    this.isGeneric = false,
    this.isFailable = false,
    this.isMutating = false,
    this.synthesized = false,
    this.availability = const SwiftAvailability(),
  });

  /// Precise identifier.
  final String usr;

  /// Kind.
  final SwiftMemberKind kind;

  /// Swift name, e.g. `increment(by:)` or `value`.
  final String title;

  /// Base name, e.g. `increment`.
  final String baseName;

  /// Parameters (methods and initializers).
  final List<SwiftParam> params;

  /// Return or property type.
  final SwiftType returnType;

  /// Declaration text.
  final String declaration;

  /// Property with a public setter.
  final bool settable;

  /// `async`.
  final bool isAsync;

  /// `throws`.
  final bool throws;

  /// Has generic parameters.
  final bool isGeneric;

  /// `init?` / `init!`.
  final bool isFailable;

  /// `mutating`.
  final bool isMutating;

  /// Compiler-synthesized (conformance members).
  final bool synthesized;

  /// iOS availability.
  final SwiftAvailability availability;

  /// External labels (`increment(by:)` -> `[by]`; `_` for unlabeled).
  List<String> get labels => [for (final p in params) p.label];
}

/// Kind of a Swift type declaration.
enum SwiftDeclKind {
  /// `class`.
  classType,

  /// `struct`.
  structType,

  /// `enum`.
  enumType,

  /// `protocol`.
  protocolType,

  /// Other (typealias, actor, ...).
  other,
}

/// One public type with its members.
final class SwiftTypeDecl {
  /// Creates a type.
  SwiftTypeDecl({
    required this.usr,
    required this.name,
    required this.kind,
    required this.declaration,
    this.isGeneric = false,
    this.inheritsFrom = const [],
    this.availability = const SwiftAvailability(),
  });

  /// Precise identifier.
  final String usr;

  /// Simple name.
  final String name;

  /// Kind.
  final SwiftDeclKind kind;

  /// Declaration text.
  final String declaration;

  /// Has generic parameters.
  final bool isGeneric;

  /// Superclass USRs (`inheritsFrom` relationships).
  final List<String> inheritsFrom;

  /// iOS availability.
  final SwiftAvailability availability;

  /// Members (in symbol-graph order).
  final members = <SwiftMember>[];

  /// Whether the class is an Objective-C class (NSObject subclass) and so
  /// already visible through the generated Objective-C header.
  bool get objcVisible => inheritsFrom.contains('c:objc(cs)NSObject');
}

/// A module's public Swift API read from a symbol graph produced by the
/// official `swift-symbolgraph-extract` tool.
final class SwiftModuleGraph {
  SwiftModuleGraph._(this.name, this.types, this.generator);

  /// Parses a `<Module>.symbols.json` document.
  factory SwiftModuleGraph.parse(String json) {
    final doc = jsonDecode(json) as Map<String, Object?>;
    final module = (doc['module']! as Map)['name'] as String;
    final generator = '${(doc['metadata']! as Map)['generator'] ?? ''}';
    final symbols = [
      for (final s in doc['symbols']! as List) s as Map<String, Object?>,
    ];
    final rels = [
      for (final r in doc['relationships']! as List) r as Map<String, Object?>,
    ];
    final types = <String, SwiftTypeDecl>{};
    final inherits = <String, List<String>>{};
    for (final r in rels) {
      if (r['kind'] == 'inheritsFrom') {
        (inherits[r['source']! as String] ??= []).add(r['target']! as String);
      }
    }
    for (final s in symbols) {
      final kind = _declKind(_kindOf(s));
      if (kind == null) continue;
      final usr = _usr(s);
      types[usr] = SwiftTypeDecl(
        usr: usr,
        name: (s['pathComponents']! as List).join('.'),
        kind: kind,
        declaration: _text(s['declarationFragments']),
        isGeneric: s['swiftGenerics'] != null,
        inheritsFrom: inherits[usr] ?? const [],
        availability: SwiftAvailability.parse(s['availability']),
      );
    }
    final owner = <String, String>{};
    for (final r in rels) {
      if (r['kind'] == 'memberOf') {
        owner[r['source']! as String] = r['target']! as String;
      }
    }
    for (final s in symbols) {
      final k = _kindOf(s);
      if (_declKind(k) != null) continue;
      final usr = _usr(s);
      final t = types[owner[usr]];
      if (t == null) continue; // free functions/extensions on other modules
      t.members.add(_member(s, k, usr));
    }
    final sorted = types.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return SwiftModuleGraph._(module, sorted, generator);
  }

  /// Reads [path].
  factory SwiftModuleGraph.read(String path) =>
      SwiftModuleGraph.parse(File(path).readAsStringSync());

  /// Module name.
  final String name;

  /// Public types, sorted by name.
  final List<SwiftTypeDecl> types;

  /// `metadata.generator` (Swift compiler version).
  final String generator;

  static String _kindOf(Map<String, Object?> s) =>
      (s['kind']! as Map)['identifier'] as String;

  static String _usr(Map<String, Object?> s) =>
      (s['identifier']! as Map)['precise'] as String;

  static SwiftDeclKind? _declKind(String k) => switch (k) {
    'swift.class' => SwiftDeclKind.classType,
    'swift.struct' => SwiftDeclKind.structType,
    'swift.enum' => SwiftDeclKind.enumType,
    'swift.protocol' => SwiftDeclKind.protocolType,
    'swift.typealias' || 'swift.actor' => SwiftDeclKind.other,
    _ => null,
  };

  static List<Map<String, Object?>> _frags(Object? f) => [
    for (final x in (f as List?) ?? const []) x as Map<String, Object?>,
  ];

  static String _text(Object? f) =>
      _frags(f).map((x) => x['spelling'] as String).join();

  static SwiftMember _member(Map<String, Object?> s, String kind, String usr) {
    final decl = _frags(s['declarationFragments']);
    final keywords = {
      for (final f in decl)
        if (f['kind'] == 'keyword') f['spelling'] as String,
    };
    final title = (s['pathComponents']! as List).last as String;
    final paren = title.indexOf('(');
    final base = paren < 0 ? title : title.substring(0, paren);
    final labels = paren < 0
        ? const <String>[]
        : title
              .substring(paren + 1, title.length - 1)
              .split(':')
              .where((l) => l.isNotEmpty)
              .toList();
    final sig = s['functionSignature'] as Map<String, Object?>?;
    final params = <SwiftParam>[];
    if (sig != null) {
      final ps = (sig['parameters'] as List?) ?? const [];
      for (var i = 0; i < ps.length; i++) {
        final p = ps[i] as Map<String, Object?>;
        final frags = _frags(p['declarationFragments']);
        // Drop the leading name fragment and ": ".
        final typeFrags = <Map<String, Object?>>[];
        var seenColon = false;
        for (final f in frags) {
          if (!seenColon) {
            if (f['kind'] == 'text' &&
                (f['spelling'] as String).contains(':')) {
              seenColon = true;
              final rest = (f['spelling'] as String)
                  .split(':')
                  .skip(1)
                  .join(':')
                  .trimLeft();
              if (rest.isNotEmpty) {
                typeFrags.add({'kind': 'text', 'spelling': rest});
              }
            }
            continue;
          }
          typeFrags.add(f);
        }
        params.add(
          SwiftParam(
            i < labels.length ? labels[i] : '_',
            (p['internalName'] ?? p['name']) as String? ?? 'p$i',
            parseType(typeFrags),
          ),
        );
      }
    }
    final memberKind = switch (kind) {
      'swift.init' => SwiftMemberKind.initializer,
      'swift.method' => SwiftMemberKind.method,
      'swift.type.method' || 'swift.class.method' => SwiftMemberKind.typeMethod,
      'swift.property' => SwiftMemberKind.property,
      'swift.type.property' ||
      'swift.class.property' => SwiftMemberKind.typeProperty,
      _ => SwiftMemberKind.other,
    };
    SwiftType ret;
    var settable = false;
    if (memberKind == SwiftMemberKind.property ||
        memberKind == SwiftMemberKind.typeProperty) {
      // `var name: Type { get }` / `var name: Type` / `let name: Type`.
      final typeFrags = <Map<String, Object?>>[];
      var seenColon = false;
      for (final f in decl) {
        final sp = f['spelling'] as String;
        if (!seenColon) {
          if (f['kind'] == 'text' && sp.contains(':')) {
            seenColon = true;
            final rest = sp.split(':').skip(1).join(':').trimLeft();
            if (rest.isNotEmpty) {
              typeFrags.add({'kind': 'text', 'spelling': rest});
            }
          }
          continue;
        }
        if (f['kind'] == 'text' && sp.contains('{')) {
          final before = sp.substring(0, sp.indexOf('{')).trimRight();
          if (before.isNotEmpty) {
            typeFrags.add({'kind': 'text', 'spelling': before});
          }
          break;
        }
        if (f['kind'] == 'keyword' && (sp == 'get' || sp == 'set')) break;
        typeFrags.add(f);
      }
      ret = parseType(typeFrags);
      final text = _text(decl);
      settable =
          !keywords.contains('let') &&
          (!text.contains('{') || text.contains('set'));
    } else if (sig != null) {
      final r = _frags(sig['returns']);
      ret = parseType(r);
    } else {
      ret = const SwiftVoid();
    }
    return SwiftMember(
      usr: usr,
      kind: memberKind,
      title: title,
      baseName: base,
      params: params,
      returnType: ret,
      declaration: _text(decl),
      settable: settable,
      isAsync: keywords.contains('async'),
      throws: keywords.contains('throws') || keywords.contains('rethrows'),
      isGeneric: s['swiftGenerics'] != null,
      isFailable:
          memberKind == SwiftMemberKind.initializer &&
          RegExp(r'init[?!]').hasMatch(_text(decl)),
      isMutating: keywords.contains('mutating'),
      synthesized: usr.contains('::SYNTHESIZED::'),
      availability: SwiftAvailability.parse(s['availability']),
    );
  }

  /// Classifies a type from declaration fragments.
  static SwiftType parseType(List<Map<String, Object?>> frags) {
    final text = frags.map((f) => f['spelling'] as String).join().trim();
    if (text.isEmpty || text == '()' || text == 'Void') {
      return const SwiftVoid();
    }
    final ids = [
      for (final f in frags)
        if (f['kind'] == 'typeIdentifier') f,
    ];
    final rest = frags
        .where((f) => f['kind'] != 'typeIdentifier')
        .map((f) => f['spelling'] as String)
        .join()
        .trim();
    final isGenericParam =
        ids.isNotEmpty &&
        ids.every((f) => f['preciseIdentifier'] == null) &&
        RegExp(r'^[A-Z]\w*[?!]?$').hasMatch(text);
    if (text.contains('->')) {
      return SwiftOther(
        text,
        DiagnosticCode.unsupportedCallback,
        'Swift closures need a block bridge (planned)',
      );
    }
    if (text.startsWith('(')) {
      return SwiftOther(
        text,
        DiagnosticCode.unsupportedType,
        'Tuples are not representable in Objective-C',
      );
    }
    if (text.startsWith('[')) {
      return SwiftOther(
        text,
        DiagnosticCode.unsupportedType,
        'Swift collections are not bridged yet (planned)',
      );
    }
    if (text.startsWith('some ') ||
        text.startsWith('any ') ||
        text.startsWith('inout ')) {
      return SwiftOther(
        text,
        DiagnosticCode.unsupportedType,
        'Opaque, existential and inout types are not representable in Objective-C',
      );
    }
    if (isGenericParam) {
      return SwiftOther(
        text,
        DiagnosticCode.unsupportedGeneric,
        'Generic parameters are not representable in Objective-C',
      );
    }
    if (ids.length == 1 && (rest.isEmpty || rest == '?' || rest == '!')) {
      final f = ids.single;
      return SwiftNamed(
        text,
        f['spelling'] as String,
        f['preciseIdentifier'] as String?,
        optional: rest.isNotEmpty,
      );
    }
    return SwiftOther(
      text,
      text.contains('<')
          ? DiagnosticCode.unsupportedGeneric
          : DiagnosticCode.unsupportedType,
      'Type $text is not representable in Objective-C',
    );
  }
}
