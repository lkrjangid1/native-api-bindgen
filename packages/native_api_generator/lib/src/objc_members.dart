import 'package:native_api_ir/native_api_ir.dart';

/// One target-visible instance or static member of an Objective-C type: a
/// method, or a property (getter plus optional setter).
final class ObjCMember {
  /// Creates a member.
  ObjCMember(
    this.key,
    this.owner, {
    this.method,
    this.property,
    required this.isStatic,
  });

  /// `-sel` / `+sel` for methods, `P-name` / `P+name` for properties.
  final String key;

  /// Declaring type.
  final ApiType owner;

  /// The method, for method members.
  final ApiMethod? method;

  /// The property, for property members.
  final ApiProperty? property;

  /// Class (`+`) member.
  final bool isStatic;
}

/// Member names of one type, consistent through inheritance.
final class ObjCMemberNames {
  /// Instance members visible (declared + inherited) by key.
  final visible = <String, ObjCMember>{};

  /// key -> target name (instance members).
  final keyToName = <String, String>{};

  /// Declared members of this type with their target names.
  final declared = <(ObjCMember, String)>[];

  /// Inherited names that conflict between supertypes: name -> provider.
  final conflicts = <String, ObjCMember>{};
}

/// First selector keyword (`addItem:atIndex:` -> `addItem`).
String objcFirstKeyword(String selector) {
  final i = selector.indexOf(':');
  return i < 0 ? selector : selector.substring(0, i);
}

/// Selector keywords (`addItem:atIndex:` -> `[addItem, atIndex]`).
List<String> objcKeywords(String selector) =>
    selector.split(':').where((k) => k.isNotEmpty).toList();

/// Resolves which members each Objective-C type exposes and their names in
/// a target language. An override keeps the inherited name; collisions get
/// the remaining selector keywords appended (`addItem$atIndex`), then `$`.
final class ObjCMemberResolver {
  /// Creates a resolver over [types] (all planned types by id). [escape]
  /// turns a base name into a valid target identifier; [reserved] names are
  /// never assigned (runtime members of the target base class).
  ObjCMemberResolver(
    this.types, {
    required this.escape,
    required this.reserved,
    this.staticReserved = const {},
  });

  /// All types by id.
  final Map<String, ApiType> types;

  /// Target identifier escaping.
  final String Function(String) escape;

  /// Names never assigned to members.
  final Set<String> reserved;

  /// Additional names never assigned to class (static) members.
  final Set<String> staticReserved;

  final _cache = <String, ObjCMemberNames>{};

  /// Direct supertypes (superclass first, then protocols) present in [types].
  List<ApiType> directSupers(ApiType t) => [
    for (final s in [?t.superClass, ...t.interfaces])
      ?types[(s as DeclaredTypeRef).name],
  ];

  /// Key of a property member.
  static String propertyKey(ApiProperty p) =>
      'P${p.getterId.contains('#+') ? '+' : '-'}${p.name}';

  /// Whether [p]'s getter can be generated.
  static bool propertySupported(ApiType t, ApiProperty p) {
    final getter = t.methods.where((m) => m.id == p.getterId).firstOrNull;
    return getter != null && getter.isGeneratable;
  }

  /// Member names of [t].
  ObjCMemberNames names(ApiType t) {
    final cached = _cache[t.id];
    if (cached != null) return cached;
    final r = ObjCMemberNames();
    final providers = <String, Set<String>>{}; // name -> super ids
    final firstProvider = <String, ObjCMember>{};
    for (final s in directSupers(t)) {
      final sn = names(s);
      for (final e in sn.visible.entries) {
        r.visible.putIfAbsent(e.key, () => e.value);
        final name = sn.keyToName[e.key]!;
        r.keyToName.putIfAbsent(e.key, () => name);
        (providers[name] ??= {}).add(s.id);
        firstProvider.putIfAbsent(name, () => e.value);
      }
    }
    final inheritedNames = <String, String>{}; // name -> key
    r.keyToName.forEach((k, n) => inheritedNames.putIfAbsent(n, () => k));
    final taken = <String>{...inheritedNames.keys, ...reserved};

    String fresh(String base, List<String> keywords) {
      var name = escape(base);
      if (!taken.add(name)) {
        name = escape([base, ...keywords.skip(1)].join(r'$'));
        while (!taken.add(name)) {
          name = '$name\$';
        }
      }
      return name;
    }

    final accessors = {
      for (final p in t.properties) ...[p.getterId, ?p.setterId],
    };
    final declaredRaw = <ObjCMember>[
      for (final p
          in t.properties.toList()..sort((a, b) => a.name.compareTo(b.name)))
        if (propertySupported(t, p))
          ObjCMember(
            propertyKey(p),
            t,
            property: p,
            isStatic: p.getterId.contains('#+'),
          ),
      for (final m in t.methods.toList()..sort((a, b) => a.id.compareTo(b.id)))
        if (m.isGeneratable && !accessors.contains(m.id))
          ObjCMember(
            '${m.isStatic ? '+' : '-'}${m.name}',
            t,
            method: m,
            isStatic: m.isStatic,
          ),
    ];
    // Categories can redeclare a member: keep the first declaration per key.
    final seenKeys = <String>{};
    final declared = [
      for (final m in declaredRaw)
        if (seenKeys.add(m.key)) m,
    ];
    List<String> kw(ObjCMember m) =>
        m.method == null ? const [] : objcKeywords(m.method!.name);
    String base(ObjCMember m) =>
        m.property?.name ?? objcFirstKeyword(m.method!.name);
    for (final m in declared.where((m) => !m.isStatic)) {
      // An override keeps the inherited name.
      final name = r.keyToName[m.key] ?? fresh(base(m), kw(m));
      r.keyToName[m.key] = name;
      r.visible[m.key] = m;
      r.declared.add((m, name));
    }
    taken.addAll(staticReserved);
    for (final m in declared.where((m) => m.isStatic)) {
      r.declared.add((m, fresh(base(m), kw(m))));
    }
    final declaredNames = {for (final (_, n) in r.declared) n};
    providers.forEach((name, from) {
      if (from.length > 1 && !declaredNames.contains(name)) {
        r.conflicts[name] = firstProvider[name]!;
      }
    });
    return _cache[t.id] = r;
  }
}
