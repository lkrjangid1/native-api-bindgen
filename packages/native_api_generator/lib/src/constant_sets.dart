import 'package:native_api_ir/native_api_ir.dart';

/// A typed set of SDK constants derived from `@IntDef` / `@LongDef` /
/// `@StringDef` usages (TRD §11, §61). The Android SDK inlines these
/// annotations at each use site (they have no public name), so sets are
/// keyed by their owner type and a name derived from the constants' common
/// name prefix (`SHOW_MODE_AUTO`, `SHOW_MODE_HIDDEN` -> `ShowMode`).
/// Values are the SDK's constants, never altered.
final class ConstantSet {
  /// Creates a set.
  ConstantSet(this.owner, this.name, this.kind, this.flag, this.members);

  /// Type declaring every member constant.
  final ApiType owner;

  /// PascalCase name, unique within [owner].
  final String name;

  /// `int`, `long` or `string`.
  final String kind;

  /// Whether values may be combined as bit flags.
  final bool flag;

  /// Member constants, sorted by name.
  final List<ApiField> members;

  /// Symbol IDs of the fields and methods (results, or `parameter N`) typed
  /// by this set.
  final usages = <String>{};
}

/// The constant sets of a module and where they are used.
final class ConstantSets {
  ConstantSets._();

  /// Derives the sets of [module]'s generatable members.
  factory ConstantSets.of(ApiModule module) {
    final r = ConstantSets._();
    final types = <String, ApiType>{
      for (final t in module.types)
        if (t.isGeneratable) t.id.replaceAll(r'$', '.'): t,
    };
    // name key -> candidate; merged when the name, kind and flag agree.
    final byName = <String, _Candidate>{};
    final conflicting = <String>{};

    void use(String site, List<ApiAnnotation> anns, TypeRef type) {
      for (final a in anns) {
        final kind = switch (a.simpleName) {
          'IntDef' => 'int',
          'LongDef' => 'long',
          'StringDef' => 'string',
          _ => null,
        };
        if (kind == null || !_typeMatches(kind, type)) continue;
        final c = _resolve(types, a, kind);
        if (c == null) {
          r.unresolved++;
          continue;
        }
        final key = '${c.owner.id} ${c.name}';
        final prev = byName[key];
        if (prev == null) {
          byName[key] = c;
        } else if (prev.kind != c.kind || prev.flag != c.flag) {
          conflicting.add(key);
        } else {
          prev.members.addAll(c.members);
        }
        byName[key]!.sites.add(site);
      }
    }

    for (final t in module.types.where((t) => t.isGeneratable)) {
      for (final f in t.fields.where((f) => f.isGeneratable)) {
        use('F:${f.id}', f.annotations, f.type);
      }
      for (final m in t.methods.where((m) => m.isGeneratable)) {
        if (m.asyncKind == AsyncKind.suspend) continue;
        use('R:${m.id}', m.annotations, m.returnType);
        for (var i = 0; i < m.parameters.length; i++) {
          final p = m.parameters[i];
          use('P:${m.id}#$i', p.annotations, p.type);
        }
      }
    }
    for (final key in (byName.keys.toList()..sort())) {
      if (conflicting.contains(key)) {
        r.unnamed += byName[key]!.sites.length;
        continue;
      }
      final c = byName[key]!;
      final s = ConstantSet(
        c.owner,
        c.name,
        c.kind,
        c.flag,
        c.members.toList()..sort((a, b) => a.name.compareTo(b.name)),
      );
      for (final site in c.sites) {
        r._bySite[site] = s;
        s.usages.add(_siteLabel(site));
      }
      (r._byOwner[c.owner.id] ??= []).add(s);
    }
    return r;
  }

  final _bySite = <String, ConstantSet>{};
  final _byOwner = <String, List<ConstantSet>>{};

  /// Usages whose constants could not be resolved to one generated owner
  /// (constants outside the module, mixed owners, or no derivable name).
  int unresolved = 0;

  /// Usages dropped because two different sets derived the same name.
  int unnamed = 0;

  /// Set typing parameter [index] of [methodId], if any.
  ConstantSet? forParameter(String methodId, int index) =>
      _bySite['P:$methodId#$index'];

  /// Set typing the result of [methodId], if any.
  ConstantSet? forReturn(String methodId) => _bySite['R:$methodId'];

  /// Set typing field [fieldId], if any.
  ConstantSet? forField(String fieldId) => _bySite['F:$fieldId'];

  /// Sets whose constants [typeId] declares, sorted by name.
  List<ConstantSet> declaredBy(String typeId) =>
      _byOwner[typeId] ?? const <ConstantSet>[];

  /// All sets, sorted by owner then name.
  List<ConstantSet> get all => [
    for (final k in (_byOwner.keys.toList()..sort())) ..._byOwner[k]!,
  ];

  /// Number of typed use sites.
  int get typedUsages => _bySite.length;
}

final class _Candidate {
  _Candidate(this.owner, this.name, this.kind, this.flag, this.members);
  final ApiType owner;
  final String name;
  final String kind;
  final bool flag;
  final Set<ApiField> members;
  final sites = <String>{};
}

/// `P:<method>#2` -> `<method> parameter 2`; other sites -> the symbol ID.
String _siteLabel(String site) {
  final id = site.substring(2);
  if (!site.startsWith('P:')) return id;
  final i = id.lastIndexOf('#');
  return '${id.substring(0, i)} parameter ${id.substring(i + 1)}';
}

bool _typeMatches(String kind, TypeRef t) => switch (kind) {
  'int' => t is PrimitiveTypeRef && t.kind == PrimitiveKind.int_,
  'long' => t is PrimitiveTypeRef && t.kind == PrimitiveKind.long,
  _ => t is DeclaredTypeRef && t.name == 'java.lang.String',
};

const _valueTypes = {
  'int': {'int', 'short', 'byte', 'char'},
  'long': {'long', 'int', 'short', 'byte', 'char'},
  'string': {'string'},
};

_Candidate? _resolve(Map<String, ApiType> types, ApiAnnotation a, String kind) {
  final raw = a.values['value'];
  if (raw == null) return null;
  final refs = [
    for (final s
        in (raw.startsWith('{') && raw.endsWith('}')
                ? raw.substring(1, raw.length - 1)
                : raw)
            .split(','))
      if (s.trim().isNotEmpty) s.trim(),
  ];
  if (refs.isEmpty) return null;
  ApiType? owner;
  final members = <ApiField>{};
  for (final ref in refs) {
    final dot = ref.lastIndexOf('.');
    if (dot <= 0) return null;
    final t = types[ref.substring(0, dot)];
    if (t == null || (owner != null && owner.id != t.id)) return null;
    owner = t;
    final name = ref.substring(dot + 1);
    final f = t.fields
        .where(
          (f) =>
              f.name == name &&
              f.isStatic &&
              f.isGeneratable &&
              f.constantValue != null &&
              _valueTypes[kind]!.contains(f.constantValue!.type),
        )
        .firstOrNull;
    if (f == null) return null;
    members.add(f);
  }
  final name = _setName([for (final f in members) f.name]);
  if (name == null) return null;
  return _Candidate(owner!, name, kind, a.values['flag'] == 'true', members);
}

/// PascalCase of the constants' common `_`-separated prefix (or suffix):
/// `SHOW_MODE_AUTO`, `SHOW_MODE_HIDDEN` -> `ShowMode`; `POWER_SERVICE`,
/// `WINDOW_SERVICE` -> `Service`. A single constant uses all but its last
/// token. Null when nothing is shared.
String? _setName(List<String> names) {
  final tokens = [for (final n in names) n.split('_')];
  List<String> common(List<List<String>> ts) {
    final out = <String>[];
    for (var i = 0; ; i++) {
      if (ts.any((t) => i >= t.length - 1)) break; // keep a distinct tail
      final w = ts.first[i];
      if (ts.any((t) => t[i] != w)) break;
      out.add(w);
    }
    return out;
  }

  var shared = common(tokens);
  if (shared.isEmpty) {
    shared = common([
      for (final t in tokens) t.reversed.toList(),
    ]).reversed.toList();
  }
  shared = [
    for (final s in shared)
      if (s.isNotEmpty) s,
  ];
  if (shared.isEmpty) return null;
  final name = shared
      .map((s) => s[0].toUpperCase() + s.substring(1).toLowerCase())
      .join();
  if (!RegExp(r'^[A-Z][A-Za-z0-9]*$').hasMatch(name)) return null;
  return name;
}
