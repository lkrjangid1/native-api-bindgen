import 'json_util.dart';

/// Nullability of a reference type.
enum Nullability {
  /// Annotated non-null by an official annotation.
  nonnull,

  /// Annotated nullable by an official annotation.
  nullable,

  /// No nullability information. Generators must treat it as nullable.
  unknown,
}

/// Primitive kinds shared by the JVM and C-family platforms.
enum PrimitiveKind {
  /// `void` (return types only).
  void_('void', 'V'),

  /// `boolean`.
  boolean('boolean', 'Z'),

  /// 8-bit signed.
  byte('byte', 'B'),

  /// 16-bit UTF-16 code unit.
  char('char', 'C'),

  /// 16-bit signed.
  short('short', 'S'),

  /// 32-bit signed.
  int_('int', 'I'),

  /// 64-bit signed.
  long('long', 'J'),

  /// 32-bit IEEE 754.
  float('float', 'F'),

  /// 64-bit IEEE 754.
  double_('double', 'D'),

  /// C unsigned 8-bit (Apple). Not a JVM type.
  uint8('uint8', '~u8'),

  /// C unsigned 16-bit (Apple). Not a JVM type.
  uint16('uint16', '~u16'),

  /// C unsigned 32-bit (Apple). Not a JVM type.
  uint32('uint32', '~u32'),

  /// C unsigned 64-bit, e.g. `NSUInteger` on 64-bit Apple platforms.
  uint64('uint64', '~u64');

  const PrimitiveKind(this.javaName, this.descriptor);

  /// Java keyword.
  final String javaName;

  /// JVM descriptor character.
  final String descriptor;

  /// Looks up by Java keyword.
  static PrimitiveKind byJavaName(String name) => values.firstWhere(
    (p) => p.javaName == name,
    orElse: () => throw FormatException('Unknown primitive "$name"'),
  );

  /// Looks up by descriptor character.
  static PrimitiveKind? byDescriptor(String c) {
    for (final p in values) {
      if (p.descriptor == c) return p;
    }
    return null;
  }
}

/// A reference to a type in a signature.
///
/// Platform-neutral: Java/Kotlin types use [DeclaredTypeRef] with binary
/// names (`java.util.Map$Entry`); Objective-C will use the same node kinds.
sealed class TypeRef {
  const TypeRef();

  /// Decodes from JSON.
  factory TypeRef.fromJson(Map<String, Object?> json, [int depth = 0]) {
    if (depth > maxJsonDepth) {
      throw const FormatException('Type nesting too deep');
    }
    final kind = json.str('kind');
    final nullability = json.enumValue(
      'nullability',
      Nullability.values,
      fallback: Nullability.unknown,
    );
    switch (kind) {
      case 'primitive':
        return PrimitiveTypeRef(PrimitiveKind.byJavaName(json.str('name')));
      case 'declared':
        return DeclaredTypeRef(
          json.str('name'),
          typeArguments: json.list(
            'typeArguments',
            (j) => TypeRef.fromJson(j, depth + 1),
          ),
          nullability: nullability,
        );
      case 'typeVariable':
        return TypeVariableRef(json.str('name'), nullability: nullability);
      case 'wildcard':
        final bound = json.objOrNull('bound');
        return WildcardTypeRef(
          bound == null ? null : TypeRef.fromJson(bound, depth + 1),
          isSuper: json.boolOr('super', false),
        );
      case 'array':
        return ArrayTypeRef(
          TypeRef.fromJson(json.obj('component'), depth + 1),
          nullability: nullability,
        );
      case 'pointer':
        return PointerTypeRef(
          TypeRef.fromJson(json.obj('pointee'), depth + 1),
          nullability: nullability,
        );
      case 'block':
        return BlockTypeRef(
          TypeRef.fromJson(json.obj('returnType'), depth + 1),
          json.list('parameters', (j) => TypeRef.fromJson(j, depth + 1)),
          nullability: nullability,
        );
      default:
        throw FormatException('Unknown type kind "$kind"');
    }
  }

  /// Nullability (always [Nullability.nonnull] for primitives).
  Nullability get nullability;

  /// Fully erased form used inside stable symbol IDs, e.g. `java.lang.String`,
  /// `int[]`, `java.util.List`.
  String get erasedId;

  /// Readable Java-like spelling including generics, e.g.
  /// `java.util.List<? extends E>`.
  String get display;

  /// Binary names of all declared types referenced (for dependency graphs).
  Iterable<String> get referencedTypes;

  /// Copy with different nullability (no-op for primitives and wildcards).
  TypeRef withNullability(Nullability n);

  /// JSON form.
  Map<String, Object?> toJson();

  @override
  String toString() => display;
}

/// A primitive type.
final class PrimitiveTypeRef extends TypeRef {
  /// Creates a primitive type reference.
  const PrimitiveTypeRef(this.kind);

  /// The primitive.
  final PrimitiveKind kind;

  @override
  Nullability get nullability => Nullability.nonnull;

  @override
  String get erasedId => kind.javaName;

  @override
  String get display => kind.javaName;

  @override
  Iterable<String> get referencedTypes => const [];

  @override
  TypeRef withNullability(Nullability n) => this;

  @override
  Map<String, Object?> toJson() => {'kind': 'primitive', 'name': kind.javaName};

  @override
  bool operator ==(Object other) =>
      other is PrimitiveTypeRef && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}

/// A class/interface/enum type, optionally parameterized.
final class DeclaredTypeRef extends TypeRef {
  /// Creates a declared type reference. [name] is the binary name with `.`
  /// package separators and `$` for nesting: `android.os.Handler$Callback`.
  const DeclaredTypeRef(
    this.name, {
    this.typeArguments = const [],
    this.nullability = Nullability.unknown,
  });

  /// Binary name.
  final String name;

  /// Type arguments (empty for raw / non-generic use).
  final List<TypeRef> typeArguments;

  @override
  final Nullability nullability;

  @override
  String get erasedId => name;

  @override
  String get display => typeArguments.isEmpty
      ? name
      : '$name<${typeArguments.map((t) => t.display).join(', ')}>';

  @override
  Iterable<String> get referencedTypes sync* {
    yield name;
    for (final a in typeArguments) {
      yield* a.referencedTypes;
    }
  }

  @override
  DeclaredTypeRef withNullability(Nullability n) =>
      DeclaredTypeRef(name, typeArguments: typeArguments, nullability: n);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'declared',
    'name': name,
    if (typeArguments.isNotEmpty)
      'typeArguments': [for (final t in typeArguments) t.toJson()],
    'nullability': nullability.name,
  };

  @override
  bool operator ==(Object other) =>
      other is DeclaredTypeRef &&
      other.name == name &&
      other.nullability == nullability &&
      _listEq(other.typeArguments, typeArguments);

  @override
  int get hashCode =>
      Object.hash(name, nullability, Object.hashAll(typeArguments));
}

/// A reference to a type variable such as `T`.
final class TypeVariableRef extends TypeRef {
  /// Creates a type-variable reference.
  const TypeVariableRef(this.name, {this.nullability = Nullability.unknown});

  /// Variable name.
  final String name;

  @override
  final Nullability nullability;

  /// Type variables erase to their first bound; callers that know the bound
  /// should use it. Without context the erasure is `java.lang.Object`.
  @override
  String get erasedId => 'java.lang.Object';

  @override
  String get display => name;

  @override
  Iterable<String> get referencedTypes => const [];

  @override
  TypeVariableRef withNullability(Nullability n) =>
      TypeVariableRef(name, nullability: n);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'typeVariable',
    'name': name,
    'nullability': nullability.name,
  };

  @override
  bool operator ==(Object other) =>
      other is TypeVariableRef &&
      other.name == name &&
      other.nullability == nullability;

  @override
  int get hashCode => Object.hash(name, nullability);
}

/// A wildcard type argument: `?`, `? extends B`, `? super B`.
final class WildcardTypeRef extends TypeRef {
  /// Creates a wildcard.
  const WildcardTypeRef(this.bound, {this.isSuper = false});

  /// Bound, or null for unbounded `?`.
  final TypeRef? bound;

  /// Whether the bound is a lower (`super`) bound.
  final bool isSuper;

  @override
  Nullability get nullability => Nullability.unknown;

  @override
  String get erasedId =>
      (isSuper || bound == null) ? 'java.lang.Object' : bound!.erasedId;

  @override
  String get display => bound == null
      ? '?'
      : '? ${isSuper ? 'super' : 'extends'} ${bound!.display}';

  @override
  Iterable<String> get referencedTypes => bound?.referencedTypes ?? const [];

  @override
  TypeRef withNullability(Nullability n) => this;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'wildcard',
    if (bound != null) 'bound': bound!.toJson(),
    if (isSuper) 'super': true,
  };

  @override
  bool operator ==(Object other) =>
      other is WildcardTypeRef &&
      other.bound == bound &&
      other.isSuper == isSuper;

  @override
  int get hashCode => Object.hash(bound, isSuper);
}

/// An array type.
final class ArrayTypeRef extends TypeRef {
  /// Creates an array reference.
  const ArrayTypeRef(this.component, {this.nullability = Nullability.unknown});

  /// Component type.
  final TypeRef component;

  @override
  final Nullability nullability;

  @override
  String get erasedId => '${component.erasedId}[]';

  @override
  String get display => '${component.display}[]';

  @override
  Iterable<String> get referencedTypes => component.referencedTypes;

  @override
  ArrayTypeRef withNullability(Nullability n) =>
      ArrayTypeRef(component, nullability: n);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'array',
    'component': component.toJson(),
    'nullability': nullability.name,
  };

  @override
  bool operator ==(Object other) =>
      other is ArrayTypeRef &&
      other.component == component &&
      other.nullability == nullability;

  @override
  int get hashCode => Object.hash(component, nullability);
}

/// A C pointer to a non-object type (`void *`, `NSError **`, `char *`).
final class PointerTypeRef extends TypeRef {
  /// Creates a pointer reference.
  const PointerTypeRef(this.pointee, {this.nullability = Nullability.unknown});

  /// Pointee type.
  final TypeRef pointee;

  @override
  final Nullability nullability;

  @override
  String get erasedId => '${pointee.erasedId}*';

  @override
  String get display => '${pointee.display} *';

  @override
  Iterable<String> get referencedTypes => pointee.referencedTypes;

  @override
  PointerTypeRef withNullability(Nullability n) =>
      PointerTypeRef(pointee, nullability: n);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'pointer',
    'pointee': pointee.toJson(),
    'nullability': nullability.name,
  };

  @override
  bool operator ==(Object other) =>
      other is PointerTypeRef &&
      other.pointee == pointee &&
      other.nullability == nullability;

  @override
  int get hashCode => Object.hash('ptr', pointee, nullability);
}

/// An Objective-C block (closure) type.
final class BlockTypeRef extends TypeRef {
  /// Creates a block reference.
  const BlockTypeRef(
    this.returnType,
    this.parameters, {
    this.nullability = Nullability.unknown,
  });

  /// Return type.
  final TypeRef returnType;

  /// Parameter types.
  final List<TypeRef> parameters;

  @override
  final Nullability nullability;

  @override
  String get erasedId =>
      'block(${parameters.map((p) => p.erasedId).join(',')})';

  @override
  String get display =>
      '${returnType.display} (^)(${parameters.map((p) => p.display).join(', ')})';

  @override
  Iterable<String> get referencedTypes sync* {
    yield* returnType.referencedTypes;
    for (final p in parameters) {
      yield* p.referencedTypes;
    }
  }

  @override
  BlockTypeRef withNullability(Nullability n) =>
      BlockTypeRef(returnType, parameters, nullability: n);

  @override
  Map<String, Object?> toJson() => {
    'kind': 'block',
    'returnType': returnType.toJson(),
    if (parameters.isNotEmpty)
      'parameters': [for (final p in parameters) p.toJson()],
    'nullability': nullability.name,
  };

  @override
  bool operator ==(Object other) =>
      other is BlockTypeRef &&
      other.returnType == returnType &&
      other.nullability == nullability &&
      _listEq(other.parameters, parameters);

  @override
  int get hashCode =>
      Object.hash('block', returnType, Object.hashAll(parameters), nullability);
}

/// A generic type parameter declaration: `T extends Comparable<T>`.
final class TypeParameter {
  /// Creates a type parameter.
  const TypeParameter(this.name, {this.bounds = const []});

  /// Decodes from JSON.
  factory TypeParameter.fromJson(Map<String, Object?> json) => TypeParameter(
    json.str('name'),
    bounds: json.list('bounds', TypeRef.fromJson),
  );

  /// Name.
  final String name;

  /// Upper bounds (class bound first, then interface bounds).
  final List<TypeRef> bounds;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    if (bounds.isNotEmpty) 'bounds': [for (final b in bounds) b.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is TypeParameter &&
      other.name == name &&
      _listEq(other.bounds, bounds);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(bounds));
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
