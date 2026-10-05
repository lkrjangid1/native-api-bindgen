import 'package:native_api_ir/native_api_ir.dart';

import 'identifiers.dart';

/// Deterministic overload naming (TRD §56, §58).
///
/// Within the set of overloads of one Java name visible in a type, the
/// *primary* overload — earliest `introduced`, then fewest parameters, then
/// lexicographically smallest JVM descriptor — keeps the plain name. Every
/// other overload gets a suffix built from the simple names of its erased
/// parameter types: `putExtra$String$intArray`. Because suffixes depend only
/// on the method's own signature, adding overloads in a newer SDK never
/// renames existing non-primary overloads. Constructors use `new` as the
/// base name (`Intent.new$String$Uri`); the primary constructor is unnamed.
final class OverloadNamer {
  /// Computes Dart names for [methods] (all overloads visible in one type).
  static Map<String, String> assign(Iterable<ApiMethod> methods) {
    final byName = <String, List<ApiMethod>>{};
    for (final m in methods) {
      (byName[m.isConstructor ? SymbolIds.constructorName : m.name] ??= []).add(
        m,
      );
    }
    final out = <String, String>{};
    for (final entry in byName.entries) {
      final group = entry.value..sort(_primaryOrder);
      final isCtor = entry.key == SymbolIds.constructorName;
      final base = isCtor ? 'new' : Identifiers.dartMember(entry.key);
      final used = <String>{};
      for (var i = 0; i < group.length; i++) {
        final m = group[i];
        String name;
        if (i == 0) {
          name = isCtor ? '' : base;
        } else {
          name = '$base\$${suffix(m)}';
          if (used.contains(name)) {
            name = '$base\$${suffix(m, qualified: true)}';
          }
          // Erasure can make suffixes collide (`m(T)` vs `m(Object)`); the
          // descriptor order index keeps names unique and deterministic.
          if (used.contains(name)) name = '$name\$$i';
        }
        used.add(name);
        out[m.id] = name;
      }
    }
    return out;
  }

  static int _primaryOrder(ApiMethod a, ApiMethod b) {
    final ia = a.availability.introduced ?? const ApiVersion(0);
    final ib = b.availability.introduced ?? const ApiVersion(0);
    final c = ia.compareTo(ib);
    if (c != 0) return c;
    final p = a.parameters.length.compareTo(b.parameters.length);
    if (p != 0) return p;
    for (var i = 0; i < a.parameters.length; i++) {
      final r = _rank(
        a.parameters[i].type,
      ).compareTo(_rank(b.parameters[i].type));
      if (r != 0) return r;
    }
    return (a.nativeDescriptor ?? a.id).compareTo(b.nativeDescriptor ?? b.id);
  }

  // Tie-break among equally old overloads: the most common/simple parameter
  // types win the plain name (int before long before double, String before
  // other objects, scalars before arrays).
  static int _rank(TypeRef t) => switch (t) {
    PrimitiveTypeRef(:final kind) => switch (kind) {
      PrimitiveKind.int_ => 0,
      PrimitiveKind.long => 1,
      PrimitiveKind.boolean => 2,
      PrimitiveKind.double_ => 3,
      PrimitiveKind.float => 4,
      PrimitiveKind.char => 5,
      PrimitiveKind.short => 6,
      PrimitiveKind.byte => 7,
      PrimitiveKind.void_ => 8,
    },
    DeclaredTypeRef(:final name) => name == 'java.lang.String' ? 10 : 11,
    TypeVariableRef() || WildcardTypeRef() => 12,
    ArrayTypeRef() => 13,
  };

  /// Signature-derived suffix: `String$int`, `intArray`, or `noArgs`.
  static String suffix(ApiMethod m, {bool qualified = false}) {
    if (m.parameters.isEmpty) return 'noArgs';
    return m.parameters.map((p) => _typeToken(p.type, qualified)).join(r'$');
  }

  static String _typeToken(TypeRef t, bool qualified) => switch (t) {
    PrimitiveTypeRef(:final kind) => kind.javaName,
    ArrayTypeRef(:final component) =>
      '${_typeToken(component, qualified)}Array',
    DeclaredTypeRef(:final name) =>
      qualified
          ? name.replaceAll(RegExp(r'[.$]'), '_')
          : name.substring(name.lastIndexOf(RegExp(r'[.$]')) + 1),
    TypeVariableRef() || WildcardTypeRef() => 'Object',
  };
}
