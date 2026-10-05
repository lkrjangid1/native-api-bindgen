import 'diagnostics.dart';
import 'json_util.dart';
import 'metadata.dart';
import 'types.dart';

/// IR schema version. Bump on any incompatible JSON change.
const int irSchemaVersion = 1;

/// Declaration modifiers (union over supported platforms).
enum Modifier {
  /// `public`.
  public,

  /// `protected`.
  protected,

  /// `static`.
  static_,

  /// `final`.
  final_,

  /// `abstract`.
  abstract_,

  /// Java interface `default` method.
  default_,

  /// `synchronized`.
  synchronized,

  /// `native`.
  native,

  /// Variable arity (`...`).
  varargs,

  /// Compiler-generated.
  synthetic,

  /// Compiler-generated bridge method.
  bridge,

  /// `transient` field.
  transient,

  /// `volatile` field.
  volatile;

  /// Stable JSON spelling (no trailing underscore).
  String get jsonName =>
      name.endsWith('_') ? name.substring(0, name.length - 1) : name;

  /// Parses [jsonName].
  static Modifier parse(String s) => values.firstWhere(
    (m) => m.jsonName == s,
    orElse: () => throw FormatException('Unknown modifier "$s"'),
  );
}

/// Kind of a type declaration.
enum TypeKind {
  /// Class.
  classType,

  /// Java interface.
  interfaceType,

  /// Enum.
  enumType,

  /// Annotation interface.
  annotationType,

  /// Record.
  recordType,

  /// C/Swift struct (planned).
  struct,

  /// Objective-C/Swift protocol (planned).
  protocol,
}

/// Kind of a callable member.
enum MethodKind {
  /// Constructor.
  constructor,

  /// Method (static or instance).
  method,
}

/// A typed compile-time constant. Stored as a literal string so that
/// NaN/Infinity and 64-bit values survive JSON exactly.
final class ConstantValue {
  /// Creates a constant.
  const ConstantValue(this.type, this.literal);

  /// Decodes from JSON.
  factory ConstantValue.fromJson(Map<String, Object?> json) =>
      ConstantValue(json.str('type'), json.str('literal'));

  /// `int`, `long`, `float`, `double`, `boolean`, `char`, `short`, `byte`,
  /// `string`.
  final String type;

  /// Exact literal. Strings are raw (unescaped) text; `char` is the decimal
  /// UTF-16 code unit; floats use Dart `toString()` or `NaN`/`Infinity`.
  final String literal;

  /// JSON form.
  Map<String, Object?> toJson() => {'type': type, 'literal': literal};

  @override
  bool operator ==(Object other) =>
      other is ConstantValue && other.type == type && other.literal == literal;

  @override
  int get hashCode => Object.hash(type, literal);

  @override
  String toString() => '$type $literal';
}

Set<Modifier> _mods(Map<String, Object?> json) => {
  for (final m in json.strings('modifiers')) Modifier.parse(m),
};

List<String> _modsJson(Set<Modifier> m) =>
    (m.map((e) => e.jsonName).toList()..sort());

List<Map<String, Object?>> _annJson(List<ApiAnnotation> a) => [
  for (final x in (a.toList()..sort())) x.toJson(),
];

/// Fields shared by every IR node.
sealed class ApiNode {
  const ApiNode({
    required this.id,
    required this.name,
    this.modifiers = const {},
    this.annotations = const [],
    this.availability = Availability.unknown,
    this.visibility = ApiVisibility.public,
    this.support = SupportStatus.supported,
    this.documentation = const Documentation(),
    this.diagnostics = const [],
  });

  /// Stable symbol ID (see `SymbolIds`).
  final String id;

  /// Simple name.
  final String name;

  /// Modifiers.
  final Set<Modifier> modifiers;

  /// Annotations.
  final List<ApiAnnotation> annotations;

  /// Availability.
  final Availability availability;

  /// Public / hidden / private.
  final ApiVisibility visibility;

  /// Whether generators may emit it.
  final SupportStatus support;

  /// Documentation metadata.
  final Documentation documentation;

  /// Diagnostics explaining partial/unsupported status.
  final List<Diagnostic> diagnostics;

  /// Whether `static`.
  bool get isStatic => modifiers.contains(Modifier.static_);

  /// Whether deprecated (via availability or a `Deprecated` annotation).
  bool get isDeprecated =>
      availability.deprecated != null ||
      annotations.any((a) => a.type == 'java.lang.Deprecated');

  /// Whether this node should be emitted by generators.
  bool get isGeneratable =>
      visibility == ApiVisibility.public &&
      support != SupportStatus.unsupported;

  Map<String, Object?> _baseJson() => {
    'id': id,
    'name': name,
    if (modifiers.isNotEmpty) 'modifiers': _modsJson(modifiers),
    if (annotations.isNotEmpty) 'annotations': _annJson(annotations),
    if (availability != Availability.unknown)
      'availability': availability.toJson(),
    'visibility': visibility.name,
    'support': support.name,
    if (documentation.sourceType != 'none' || documentation.reference != null)
      'documentation': documentation.toJson(),
    if (diagnostics.isNotEmpty)
      'diagnostics': [
        for (final d in (diagnostics.toList()..sort())) d.toJson(),
      ],
  };

  /// JSON form.
  Map<String, Object?> toJson();
}

/// Common decoded fields.
typedef _Base = ({
  String id,
  String name,
  Set<Modifier> modifiers,
  List<ApiAnnotation> annotations,
  Availability availability,
  ApiVisibility visibility,
  SupportStatus support,
  Documentation documentation,
  List<Diagnostic> diagnostics,
});

_Base _decodeBase(Map<String, Object?> json) => (
  id: json.str('id'),
  name: json.str('name'),
  modifiers: _mods(json),
  annotations: json.list('annotations', ApiAnnotation.fromJson),
  availability: json.objOrNull('availability') == null
      ? Availability.unknown
      : Availability.fromJson(json.obj('availability')),
  visibility: json.enumValue('visibility', ApiVisibility.values),
  support: json.enumValue('support', SupportStatus.values),
  documentation: json.objOrNull('documentation') == null
      ? const Documentation()
      : Documentation.fromJson(json.obj('documentation')),
  diagnostics: json.list('diagnostics', Diagnostic.fromJson),
);

/// A method or constructor parameter.
final class ApiParameter {
  /// Creates a parameter.
  const ApiParameter(
    this.name,
    this.type, {
    this.annotations = const [],
    this.nameSource = 'synthesized',
  });

  /// Decodes from JSON.
  factory ApiParameter.fromJson(Map<String, Object?> json) => ApiParameter(
    json.str('name'),
    TypeRef.fromJson(json.obj('type')),
    annotations: json.list('annotations', ApiAnnotation.fromJson),
    nameSource: json.str('nameSource'),
  );

  /// Parameter name.
  final String name;

  /// Type, including nullability.
  final TypeRef type;

  /// Parameter annotations.
  final List<ApiAnnotation> annotations;

  /// Where [name] came from: `MethodParameters`, `LocalVariableTable`,
  /// `synthesized`.
  final String nameSource;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.toJson(),
    if (annotations.isNotEmpty) 'annotations': _annJson(annotations),
    'nameSource': nameSource,
  };
}

/// A field or constant.
final class ApiField extends ApiNode {
  /// Creates a field.
  const ApiField({
    required super.id,
    required super.name,
    required this.type,
    this.constantValue,
    this.nativeDescriptor,
    super.modifiers,
    super.annotations,
    super.availability,
    super.visibility,
    super.support,
    super.documentation,
    super.diagnostics,
  });

  /// Decodes from JSON.
  factory ApiField.fromJson(Map<String, Object?> json) {
    final b = _decodeBase(json);
    return ApiField(
      id: b.id,
      name: b.name,
      type: TypeRef.fromJson(json.obj('type')),
      constantValue: json.objOrNull('constantValue') == null
          ? null
          : ConstantValue.fromJson(json.obj('constantValue')),
      nativeDescriptor: json.strOrNull('nativeDescriptor'),
      modifiers: b.modifiers,
      annotations: b.annotations,
      availability: b.availability,
      visibility: b.visibility,
      support: b.support,
      documentation: b.documentation,
      diagnostics: b.diagnostics,
    );
  }

  /// Field type.
  final TypeRef type;

  /// Compile-time constant value, if any.
  final ConstantValue? constantValue;

  /// JVM field descriptor (Android) or ObjC type encoding (Apple).
  final String? nativeDescriptor;

  /// Whether `final`.
  bool get isFinal => modifiers.contains(Modifier.final_);

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'type': type.toJson(),
    if (constantValue != null) 'constantValue': constantValue!.toJson(),
    if (nativeDescriptor != null) 'nativeDescriptor': nativeDescriptor,
  };
}

/// A method or constructor.
final class ApiMethod extends ApiNode {
  /// Creates a method.
  const ApiMethod({
    required super.id,
    required super.name,
    required this.kind,
    required this.returnType,
    this.parameters = const [],
    this.typeParameters = const [],
    this.throws = const [],
    this.threading = Threading.unspecified,
    this.permissions = const [],
    this.asyncKind = AsyncKind.none,
    this.nativeDescriptor,
    super.modifiers,
    super.annotations,
    super.availability,
    super.visibility,
    super.support,
    super.documentation,
    super.diagnostics,
  });

  /// Decodes from JSON.
  factory ApiMethod.fromJson(Map<String, Object?> json) {
    final b = _decodeBase(json);
    return ApiMethod(
      id: b.id,
      name: b.name,
      kind: json.enumValue('kind', MethodKind.values),
      returnType: TypeRef.fromJson(json.obj('returnType')),
      parameters: json.list('parameters', ApiParameter.fromJson),
      typeParameters: json.list('typeParameters', TypeParameter.fromJson),
      throws: json.list('throws', TypeRef.fromJson),
      threading: json.enumValue(
        'threading',
        Threading.values,
        fallback: Threading.unspecified,
      ),
      permissions: json.strings('permissions'),
      asyncKind: json.enumValue(
        'asyncKind',
        AsyncKind.values,
        fallback: AsyncKind.none,
      ),
      nativeDescriptor: json.strOrNull('nativeDescriptor'),
      modifiers: b.modifiers,
      annotations: b.annotations,
      availability: b.availability,
      visibility: b.visibility,
      support: b.support,
      documentation: b.documentation,
      diagnostics: b.diagnostics,
    );
  }

  /// Constructor or method.
  final MethodKind kind;

  /// Return type (`void` for constructors).
  final TypeRef returnType;

  /// Parameters.
  final List<ApiParameter> parameters;

  /// Method type parameters.
  final List<TypeParameter> typeParameters;

  /// Declared exceptions.
  final List<TypeRef> throws;

  /// Threading requirement.
  final Threading threading;

  /// Required permissions (from `RequiresPermission`).
  final List<String> permissions;

  /// Asynchrony model.
  final AsyncKind asyncKind;

  /// JVM method descriptor (Android) or selector (Apple).
  final String? nativeDescriptor;

  /// Whether this is a constructor.
  bool get isConstructor => kind == MethodKind.constructor;

  /// Whether abstract.
  bool get isAbstract => modifiers.contains(Modifier.abstract_);

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'kind': kind.name,
    'returnType': returnType.toJson(),
    if (parameters.isNotEmpty)
      'parameters': [for (final p in parameters) p.toJson()],
    if (typeParameters.isNotEmpty)
      'typeParameters': [for (final t in typeParameters) t.toJson()],
    if (throws.isNotEmpty) 'throws': [for (final t in throws) t.toJson()],
    if (threading != Threading.unspecified) 'threading': threading.name,
    if (permissions.isNotEmpty) 'permissions': permissions,
    if (asyncKind != AsyncKind.none) 'asyncKind': asyncKind.name,
    if (nativeDescriptor != null) 'nativeDescriptor': nativeDescriptor,
  };
}

/// A derived property (Java bean getter/setter pair, ObjC `@property`).
final class ApiProperty {
  /// Creates a property.
  const ApiProperty({
    required this.name,
    required this.type,
    required this.getterId,
    this.setterId,
    this.backing = 'accessor',
  });

  /// Decodes from JSON.
  factory ApiProperty.fromJson(Map<String, Object?> json) => ApiProperty(
    name: json.str('name'),
    type: TypeRef.fromJson(json.obj('type')),
    getterId: json.str('getterId'),
    setterId: json.strOrNull('setterId'),
    backing: json.str('backing'),
  );

  /// Property name.
  final String name;

  /// Value type.
  final TypeRef type;

  /// Getter member ID.
  final String getterId;

  /// Setter member ID, if writable.
  final String? setterId;

  /// `accessor` (native getter/setter) or `field`.
  final String backing;

  /// Whether read-only.
  bool get isReadOnly => setterId == null;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'name': name,
    'type': type.toJson(),
    'getterId': getterId,
    if (setterId != null) 'setterId': setterId,
    'backing': backing,
  };
}

/// A class, interface, enum, annotation, record, struct or protocol.
final class ApiType extends ApiNode {
  /// Creates a type.
  const ApiType({
    required super.id,
    required super.name,
    required this.kind,
    required this.namespace,
    required this.provenance,
    this.typeParameters = const [],
    this.superClass,
    this.interfaces = const [],
    this.enclosingType,
    this.nestedTypes = const [],
    this.fields = const [],
    this.methods = const [],
    this.properties = const [],
    this.threading = Threading.unspecified,
    super.modifiers,
    super.annotations,
    super.availability,
    super.visibility,
    super.support,
    super.documentation,
    super.diagnostics,
  });

  /// Decodes from JSON.
  factory ApiType.fromJson(Map<String, Object?> json) {
    final b = _decodeBase(json);
    final sc = json.objOrNull('superClass');
    return ApiType(
      id: b.id,
      name: b.name,
      kind: json.enumValue('kind', TypeKind.values),
      namespace: json.str('namespace'),
      provenance: Provenance.fromJson(json.obj('provenance')),
      typeParameters: json.list('typeParameters', TypeParameter.fromJson),
      superClass: sc == null ? null : TypeRef.fromJson(sc),
      interfaces: json.list('interfaces', TypeRef.fromJson),
      enclosingType: json.strOrNull('enclosingType'),
      nestedTypes: json.strings('nestedTypes'),
      fields: json.list('fields', ApiField.fromJson),
      methods: json.list('methods', ApiMethod.fromJson),
      properties: json.list('properties', ApiProperty.fromJson),
      threading: json.enumValue(
        'threading',
        Threading.values,
        fallback: Threading.unspecified,
      ),
      modifiers: b.modifiers,
      annotations: b.annotations,
      availability: b.availability,
      visibility: b.visibility,
      support: b.support,
      documentation: b.documentation,
      diagnostics: b.diagnostics,
    );
  }

  /// Declaration kind.
  final TypeKind kind;

  /// Package / module, e.g. `android.content` or `Foundation`.
  final String namespace;

  /// Source provenance.
  final Provenance provenance;

  /// Type parameters.
  final List<TypeParameter> typeParameters;

  /// Superclass (null for interfaces and roots).
  final TypeRef? superClass;

  /// Implemented / extended interfaces.
  final List<TypeRef> interfaces;

  /// Enclosing type ID for nested types.
  final String? enclosingType;

  /// IDs of member types.
  final List<String> nestedTypes;

  /// Fields.
  final List<ApiField> fields;

  /// Constructors and methods.
  final List<ApiMethod> methods;

  /// Derived properties.
  final List<ApiProperty> properties;

  /// Class-level threading requirement.
  final Threading threading;

  /// Whether an interface (Java interface or protocol).
  bool get isInterface =>
      kind == TypeKind.interfaceType || kind == TypeKind.protocol;

  /// Whether abstract.
  bool get isAbstract => modifiers.contains(Modifier.abstract_);

  /// Constructors.
  Iterable<ApiMethod> get constructors => methods.where((m) => m.isConstructor);

  /// Name relative to the namespace, e.g. `Handler$Callback`.
  String get qualifiedSimpleName =>
      namespace.isEmpty ? id : id.substring(namespace.length + 1);

  /// Returns a copy with selected fields replaced.
  ApiType copyWith({
    List<ApiField>? fields,
    List<ApiMethod>? methods,
    List<ApiProperty>? properties,
    SupportStatus? support,
    ApiVisibility? visibility,
    List<Diagnostic>? diagnostics,
    Availability? availability,
    List<ApiAnnotation>? annotations,
    Threading? threading,
  }) => ApiType(
    id: id,
    name: name,
    kind: kind,
    namespace: namespace,
    provenance: provenance,
    typeParameters: typeParameters,
    superClass: superClass,
    interfaces: interfaces,
    enclosingType: enclosingType,
    nestedTypes: nestedTypes,
    fields: fields ?? this.fields,
    methods: methods ?? this.methods,
    properties: properties ?? this.properties,
    threading: threading ?? this.threading,
    modifiers: modifiers,
    annotations: annotations ?? this.annotations,
    availability: availability ?? this.availability,
    visibility: visibility ?? this.visibility,
    support: support ?? this.support,
    documentation: documentation,
    diagnostics: diagnostics ?? this.diagnostics,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._baseJson(),
    'kind': kind.name,
    'namespace': namespace,
    'provenance': provenance.toJson(),
    if (typeParameters.isNotEmpty)
      'typeParameters': [for (final t in typeParameters) t.toJson()],
    if (superClass != null) 'superClass': superClass!.toJson(),
    if (interfaces.isNotEmpty)
      'interfaces': [for (final i in interfaces) i.toJson()],
    if (enclosingType != null) 'enclosingType': enclosingType,
    if (nestedTypes.isNotEmpty) 'nestedTypes': (nestedTypes.toList()..sort()),
    if (fields.isNotEmpty)
      'fields': [
        for (final f in (fields.toList()..sort((a, b) => a.id.compareTo(b.id))))
          f.toJson(),
      ],
    if (methods.isNotEmpty)
      'methods': [
        for (final m
            in (methods.toList()..sort((a, b) => a.id.compareTo(b.id))))
          m.toJson(),
      ],
    if (properties.isNotEmpty)
      'properties': [
        for (final p
            in (properties.toList()..sort((a, b) => a.name.compareTo(b.name))))
          p.toJson(),
      ],
    if (threading != Threading.unspecified) 'threading': threading.name,
  };
}

/// The root of an IR document: one platform SDK snapshot (or a subset).
final class ApiModule {
  /// Creates a module.
  ApiModule({
    required this.platform,
    required this.sdkVersion,
    required this.generatorVersion,
    required List<ApiType> types,
    this.sourceRevision,
    this.diagnostics = const [],
  }) : types = List.unmodifiable(
         types.toList()..sort((a, b) => a.id.compareTo(b.id)),
       );

  /// Decodes from JSON, validating structure.
  factory ApiModule.fromJson(Map<String, Object?> json) {
    final schema = json.intOrNull('schemaVersion');
    if (schema != irSchemaVersion) {
      throw FormatException(
        'Unsupported IR schemaVersion $schema (expected $irSchemaVersion)',
      );
    }
    return ApiModule(
      platform: json.enumValue('platform', ApiPlatform.values),
      sdkVersion: json.str('sdkVersion'),
      generatorVersion: json.str('generatorVersion'),
      sourceRevision: json.strOrNull('sourceRevision'),
      types: json.list('types', ApiType.fromJson),
      diagnostics: json.list('diagnostics', Diagnostic.fromJson),
    );
  }

  /// Platform.
  final ApiPlatform platform;

  /// SDK version (e.g. `36`).
  final String sdkVersion;

  /// Platform package revision, if known.
  final String? sourceRevision;

  /// Version of the generator that produced this IR.
  final String generatorVersion;

  /// Types sorted by ID.
  final List<ApiType> types;

  /// Module-level diagnostics.
  final List<Diagnostic> diagnostics;

  late final Map<String, ApiType> _byId = {for (final t in types) t.id: t};

  /// Type by ID.
  ApiType? typeById(String id) => _byId[id];

  /// All member diagnostics + type diagnostics + module diagnostics, sorted.
  List<Diagnostic> get allDiagnostics => [
    ...diagnostics,
    for (final t in types) ...[
      ...t.diagnostics,
      for (final f in t.fields) ...f.diagnostics,
      for (final m in t.methods) ...m.diagnostics,
    ],
  ]..sort();

  /// Finds a type or member by ID.
  ApiNode? nodeById(String id) {
    final hash = id.indexOf('#');
    if (hash < 0) return typeById(id);
    final type = typeById(id.substring(0, hash));
    if (type == null) return null;
    for (final m in type.methods) {
      if (m.id == id) return m;
    }
    for (final f in type.fields) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// JSON form.
  Map<String, Object?> toJson() => {
    'schemaVersion': irSchemaVersion,
    'platform': platform.name,
    'sdkVersion': sdkVersion,
    if (sourceRevision != null) 'sourceRevision': sourceRevision,
    'generatorVersion': generatorVersion,
    'types': [for (final t in types) t.toJson()],
    if (diagnostics.isNotEmpty)
      'diagnostics': [
        for (final d in (diagnostics.toList()..sort())) d.toJson(),
      ],
  };

  /// Canonical, byte-stable JSON text.
  String toCanonicalJson() => canonicalJson(toJson());
}
