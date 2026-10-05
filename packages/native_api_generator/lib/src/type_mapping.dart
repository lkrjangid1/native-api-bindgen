import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ir/native_api_ir.dart';

import 'identifiers.dart';

/// How a native type is represented in Dart over `package:jni`.
///
/// This is the single source of type-mapping truth for the Dart/JNI target
/// (TRD §14). Emitters must not hard-code mappings.
final class DartJniType {
  /// Creates a mapping.
  const DartJniType({
    required this.dartType,
    required this.jniType,
    required this.isPrimitive,
    this.argWrapper,
    this.isOpaque = false,
    this.isString = false,
    this.ergonomicString = false,
  });

  /// Dart type spelling without nullability, e.g. `int`,
  /// `android_net.Uri`, `jni$.JString`.
  final String dartType;

  /// Expression of the `package:jni` type object used for calls and field
  /// access, e.g. `jni$.jint.type`, `android_net.Uri.type`.
  final String jniType;

  /// Whether a JVM primitive (never null).
  final bool isPrimitive;

  /// Wrapper for passing the value as a JNI argument with exact width,
  /// e.g. `jni$.JValueInt` for Java `int`. Null when the value is passed
  /// as-is (`long`, `double`, `boolean`, references).
  final String? argWrapper;

  /// Whether the native type is outside the generated closure and is
  /// represented by an opaque `JObject` (diagnostic `E016`).
  final bool isOpaque;

  /// Whether `java.lang.String`.
  final bool isString;

  /// Whether the Dart side uses `String` (ergonomic-dart mode) and the
  /// emitter must convert at the boundary.
  final bool ergonomicString;
}

/// Resolves the Dart representation of generated native types.
abstract interface class DartTypeResolver {
  /// Qualified Dart name (`prefix.Name`) for a generated type, or null if the
  /// type is not generated.
  String? qualifiedName(String typeId);
}

/// Maps IR [TypeRef]s to Dart/JNI representations.
final class DartJniTypeMapper {
  /// Creates a mapper.
  DartJniTypeMapper(this.resolver, {this.mode = GenerationMode.strictNative});

  /// Generated-type resolver.
  final DartTypeResolver resolver;

  /// Mapping mode.
  final GenerationMode mode;

  static const _primitives = {
    PrimitiveKind.boolean: ('bool', 'jni\$.jboolean.type', null),
    PrimitiveKind.byte: ('int', 'jni\$.jbyte.type', 'jni\$.JValueByte'),
    PrimitiveKind.char: ('int', 'jni\$.jchar.type', 'jni\$.JValueChar'),
    PrimitiveKind.short: ('int', 'jni\$.jshort.type', 'jni\$.JValueShort'),
    PrimitiveKind.int_: ('int', 'jni\$.jint.type', 'jni\$.JValueInt'),
    PrimitiveKind.long: ('int', 'jni\$.jlong.type', null),
    PrimitiveKind.float: ('double', 'jni\$.jfloat.type', 'jni\$.JValueFloat'),
    PrimitiveKind.double_: ('double', 'jni\$.jdouble.type', null),
    PrimitiveKind.void_: ('void', 'jni\$.jvoid.type', null),
  };

  static const _primitiveArrays = {
    PrimitiveKind.boolean: 'JBooleanArray',
    PrimitiveKind.byte: 'JByteArray',
    PrimitiveKind.char: 'JCharArray',
    PrimitiveKind.short: 'JShortArray',
    PrimitiveKind.int_: 'JIntArray',
    PrimitiveKind.long: 'JLongArray',
    PrimitiveKind.float: 'JFloatArray',
    PrimitiveKind.double_: 'JDoubleArray',
  };

  /// Maps [t]. [typeVariableBounds] gives the erasure of in-scope type
  /// variables (generic type parameters are erased in this version, `E003`).
  DartJniType map(
    TypeRef t, {
    Map<String, TypeRef> typeVariableBounds = const {},
  }) {
    switch (t) {
      case PrimitiveTypeRef(:final kind):
        final (d, j, w) = _primitives[kind]!;
        return DartJniType(
          dartType: d,
          jniType: j,
          isPrimitive: true,
          argWrapper: w,
        );
      case ArrayTypeRef(:final component):
        if (component is PrimitiveTypeRef) {
          final n = _primitiveArrays[component.kind]!;
          return DartJniType(
            dartType: 'jni\$.$n',
            jniType: 'jni\$.$n.type',
            isPrimitive: false,
          );
        }
        final inner = map(component, typeVariableBounds: typeVariableBounds);
        final innerType = inner.ergonomicString
            ? 'jni\$.JString'
            : inner.dartType;
        final innerJni = inner.ergonomicString
            ? 'jni\$.JString.type'
            : inner.jniType;
        return DartJniType(
          dartType: 'jni\$.JArray<$innerType?>',
          jniType: 'jni\$.JArray.type<$innerType?>($innerJni)',
          isPrimitive: false,
          isOpaque: inner.isOpaque,
        );
      case DeclaredTypeRef(:final name):
        return _declared(name);
      case TypeVariableRef(:final name):
        final bound = typeVariableBounds[name];
        if (bound == null || bound is TypeVariableRef) {
          return _declared('java.lang.Object');
        }
        return map(bound, typeVariableBounds: const {});
      case WildcardTypeRef(:final bound, :final isSuper):
        if (bound == null || isSuper) return _declared('java.lang.Object');
        return map(bound, typeVariableBounds: typeVariableBounds);
    }
  }

  DartJniType _declared(String id) {
    if (id == 'java.lang.String') {
      final ergonomic = mode == GenerationMode.ergonomicDart;
      return DartJniType(
        dartType: ergonomic ? 'String' : 'jni\$.JString',
        jniType: 'jni\$.JString.type',
        isPrimitive: false,
        isString: true,
        ergonomicString: ergonomic,
      );
    }
    final q = resolver.qualifiedName(id);
    if (q != null) {
      return DartJniType(dartType: q, jniType: '$q.type', isPrimitive: false);
    }
    return const DartJniType(
      dartType: 'jni\$.JObject',
      jniType: 'jni\$.JObject.type',
      isPrimitive: false,
      isOpaque: true,
    );
  }

  /// Dart type spelling including `?` for references that may be null.
  /// Unknown nullability is treated as nullable (safe default).
  String dartTypeWithNullability(TypeRef t, DartJniType m) {
    if (m.isPrimitive) return m.dartType;
    return t.nullability == Nullability.nonnull ? m.dartType : '${m.dartType}?';
  }

  /// Dart name of a generated type for [type] (`Handler$Callback` →
  /// `Handler_Callback`).
  static String dartTypeName(ApiType type) =>
      Identifiers.dartType(type.qualifiedSimpleName);
}

/// How a native type is represented in TypeScript over JSI (React Native).
final class TsJsiType {
  /// Creates a mapping.
  const TsJsiType({
    required this.tsType,
    this.wrapClass,
    this.isPrimitive = false,
    this.isLong = false,
    this.isOpaque = false,
    this.arrayDepth = 0,
  });

  /// TypeScript type without `| null`, e.g. `number`, `string`,
  /// `android_net.Uri`, `number[]`.
  final String tsType;

  /// TS class used to wrap raw JSI handles returned from native, or null for
  /// values converted by the runtime (primitives, strings, primitive arrays).
  /// For object arrays this is the element class.
  final String? wrapClass;

  /// Whether a JVM primitive (never null).
  final bool isPrimitive;

  /// Whether a Java `long` (bigint in strict mode).
  final bool isLong;

  /// Whether outside the generated closure (`JavaObject`, E016).
  final bool isOpaque;

  /// Array nesting of object arrays (0 for non-arrays and primitive arrays).
  final int arrayDepth;
}

/// Resolves the TypeScript name of generated native types.
abstract interface class TsTypeResolver {
  /// Qualified TS class name for a generated type, or null.
  String? qualifiedName(String typeId);
}

/// Maps IR [TypeRef]s to TypeScript types for the JSI target (TRD §14).
final class TsJsiTypeMapper {
  /// Creates a mapper.
  TsJsiTypeMapper(this.resolver, {this.mode = TypescriptMode.strict});

  /// Generated-type resolver.
  final TsTypeResolver resolver;

  /// Mapping mode.
  final TypescriptMode mode;

  /// Maps [t]; type variables are erased to [typeVariableBounds] or Object.
  TsJsiType map(
    TypeRef t, {
    Map<String, TypeRef> typeVariableBounds = const {},
  }) {
    switch (t) {
      case PrimitiveTypeRef(:final kind):
        return switch (kind) {
          PrimitiveKind.boolean => const TsJsiType(
            tsType: 'boolean',
            isPrimitive: true,
          ),
          PrimitiveKind.void_ => const TsJsiType(
            tsType: 'void',
            isPrimitive: true,
          ),
          PrimitiveKind.long => TsJsiType(
            tsType: mode == TypescriptMode.strict ? 'bigint' : 'number',
            isPrimitive: true,
            isLong: true,
          ),
          _ => const TsJsiType(tsType: 'number', isPrimitive: true),
        };
      case ArrayTypeRef(:final component):
        if (component is PrimitiveTypeRef) {
          final e = map(component);
          return TsJsiType(tsType: '${e.tsType}[]');
        }
        final inner = map(component, typeVariableBounds: typeVariableBounds);
        if (inner.wrapClass == null) {
          return TsJsiType(tsType: '(${inner.tsType} | null)[]');
        }
        return TsJsiType(
          tsType: '(${inner.tsType} | null)[]',
          wrapClass: inner.wrapClass,
          isOpaque: inner.isOpaque,
          arrayDepth: inner.arrayDepth + 1,
        );
      case DeclaredTypeRef(:final name):
        return _declared(name);
      case TypeVariableRef(:final name):
        final bound = typeVariableBounds[name];
        if (bound == null || bound is TypeVariableRef) {
          return _declared('java.lang.Object');
        }
        return map(bound);
      case WildcardTypeRef(:final bound, :final isSuper):
        if (bound == null || isSuper) return _declared('java.lang.Object');
        return map(bound, typeVariableBounds: typeVariableBounds);
    }
  }

  TsJsiType _declared(String id) {
    if (id == 'java.lang.String') return const TsJsiType(tsType: 'string');
    final q = resolver.qualifiedName(id);
    if (q != null) return TsJsiType(tsType: q, wrapClass: q);
    return const TsJsiType(
      tsType: 'JavaObject',
      wrapClass: 'JavaObject',
      isOpaque: true,
    );
  }

  /// JNI descriptor of the *erased* type, used by the C++ runtime to convert.
  static String descriptorOf(TypeRef t) => switch (t) {
    PrimitiveTypeRef(:final kind) => kind.descriptor,
    ArrayTypeRef(:final component) => '[${descriptorOf(component)}',
    DeclaredTypeRef(:final name) => 'L${name.replaceAll('.', '/')};',
    _ => 'Ljava/lang/Object;',
  };
}
