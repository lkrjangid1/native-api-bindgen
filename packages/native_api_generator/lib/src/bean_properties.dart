import 'package:native_api_ir/native_api_ir.dart';

/// A Java bean property derived from accessor methods (TRD §60): backed by a
/// native getter and, if present, a setter. The methods stay available.
final class BeanProperty {
  /// Creates a property.
  const BeanProperty(this.name, this.getter, this.setter);

  /// Property name (`getTitle` -> `title`, `isEnabled` -> `enabled`,
  /// `getURL` -> `URL`).
  final String name;

  /// `getX()` / `isX()`.
  final ApiMethod getter;

  /// `setX(T)`, or null for a read-only property.
  final ApiMethod? setter;
}

/// `java.beans.Introspector.decapitalize` rules: `Title` -> `title`, but
/// `URL` stays `URL`.
String decapitalize(String s) {
  if (s.isEmpty) return s;
  if (s.length > 1 &&
      s[0].toUpperCase() == s[0] &&
      s[1].toUpperCase() == s[1] &&
      s[1].toLowerCase() != s[1]) {
    return s;
  }
  return s[0].toLowerCase() + s.substring(1);
}

bool _sameType(TypeRef a, TypeRef b) =>
    a.withNullability(Nullability.unknown) ==
    b.withNullability(Nullability.unknown);

/// Bean properties of the instance accessors that [t] declares and that are
/// generatable: a no-argument non-void `getX()` (or `boolean isX()`), plus
/// `void setX(T)` with the same type. Overloaded getters (another `getX`
/// with parameters) and Kotlin `suspend` accessors are skipped.
List<BeanProperty> beanProperties(ApiType t) {
  final methods = [
    for (final m in t.methods)
      if (m.isGeneratable &&
          !m.isStatic &&
          !m.isConstructor &&
          m.asyncKind != AsyncKind.suspend)
        m,
  ];
  final byName = <String, List<ApiMethod>>{};
  for (final m in methods) {
    (byName[m.name] ??= []).add(m);
  }
  final out = <String, BeanProperty>{};
  for (final m in methods) {
    if (m.parameters.isNotEmpty) continue;
    if (byName[m.name]!.length != 1) continue;
    String? base;
    final r = m.returnType;
    final isVoid = r is PrimitiveTypeRef && r.kind == PrimitiveKind.void_;
    if (isVoid) continue;
    if (m.name.length > 3 &&
        m.name.startsWith('get') &&
        m.name[3].toUpperCase() == m.name[3] &&
        m.name[3].toLowerCase() != m.name[3]) {
      base = m.name.substring(3);
    } else if (m.name.length > 2 &&
        m.name.startsWith('is') &&
        m.name[2].toUpperCase() == m.name[2] &&
        m.name[2].toLowerCase() != m.name[2] &&
        r is PrimitiveTypeRef &&
        r.kind == PrimitiveKind.boolean) {
      base = m.name.substring(2);
    }
    if (base == null) continue;
    final name = decapitalize(base);
    if (out.containsKey(name)) continue; // getX and isX both present
    final setters = [
      for (final s in byName['set$base'] ?? const <ApiMethod>[])
        if (s.parameters.length == 1 &&
            s.returnType is PrimitiveTypeRef &&
            (s.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_ &&
            _sameType(s.parameters.single.type, r))
          s,
    ];
    out[name] = BeanProperty(
      name,
      m,
      setters.length == 1 && (byName['set$base']!.length == 1)
          ? setters.single
          : null,
    );
  }
  return [for (final k in (out.keys.toList()..sort())) out[k]!];
}
