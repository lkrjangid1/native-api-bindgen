import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;

import 'annotation_rules.dart';
import 'annotations_index.dart';
import 'api_versions.dart';
import 'classfile/byte_reader.dart';
import 'classfile/class_file.dart';
import 'classfile/signatures.dart';
import 'zip_reader.dart';

/// A source of class files addressed by binary name.
abstract interface class ClassSource {
  /// Artifact file name recorded in provenance (e.g. `android.jar`).
  String get artifactName;

  /// All binary names (`android.os.Handler$Callback`), sorted.
  List<String> get classNames;

  /// Class bytes or null.
  Uint8List? read(String binaryName);
}

/// Classes inside a jar.
final class JarClassSource implements ClassSource {
  /// Creates a source over [zip].
  JarClassSource(this._zip, this.artifactName)
    : classNames = [
        for (final n in _zip.names)
          if (n.endsWith('.class') &&
              !n.startsWith('META-INF/') &&
              !n.endsWith('module-info.class'))
            n.substring(0, n.length - 6).replaceAll('/', '.'),
      ]..sort();

  /// Opens a jar file.
  factory JarClassSource.open(String path) =>
      JarClassSource(ZipReader.open(path), p.basename(path));

  final ZipReader _zip;

  @override
  final String artifactName;

  @override
  final List<String> classNames;

  @override
  Uint8List? read(String binaryName) => _zip.read(
    '${binaryName.replaceAll('.', '/')}.class',
    maxBytes: ClassFileLimits.maxBytes,
  );
}

/// Classes in a directory tree (compiled fixtures).
final class DirectoryClassSource implements ClassSource {
  /// Creates a source rooted at [root].
  DirectoryClassSource(this.root, {this.artifactName = 'fixtures'})
    : classNames = [
        for (final f in Directory(root).listSync(recursive: true))
          if (f is File && f.path.endsWith('.class'))
            p
                .relative(f.path, from: root)
                .replaceAll(r'\', '/')
                .replaceAll('/', '.')
                .replaceFirst(RegExp(r'\.class$'), ''),
      ]..sort();

  /// Root directory.
  final String root;

  @override
  final String artifactName;

  @override
  final List<String> classNames;

  @override
  Uint8List? read(String binaryName) {
    final f = File(p.join(root, '${binaryName.replaceAll('.', '/')}.class'));
    return f.existsSync() ? f.readAsBytesSync() : null;
  }
}

/// What to extract.
final class ExtractionRequest {
  /// Creates a request.
  const ExtractionRequest({
    this.packages = const [],
    this.classes = const [],
    this.entries = const [],
    this.depth = 1,
  });

  /// Whole packages (non-recursive).
  final List<String> packages;

  /// Individual classes (binary or source names).
  final List<String> classes;

  /// Dependency-aware roots.
  final List<String> entries;

  /// Dependency depth from [entries].
  final int depth;

  /// Whether nothing was requested.
  bool get isEmpty => packages.isEmpty && classes.isEmpty && entries.isEmpty;
}

/// Extraction output.
final class ExtractionResult {
  /// Creates a result.
  const ExtractionResult(this.module, this.closureDepth, this.diagnostics);

  /// IR module of all types in the closure.
  final ApiModule module;

  /// Type ID → distance from the nearest root (ancestors get their own depth).
  final Map<String, int> closureDepth;

  /// Run-level diagnostics (also attached to [module]).
  final List<Diagnostic> diagnostics;
}

/// Converts class files into Native IR (TRD §10–§13).
///
/// Signatures come only from class files; availability from
/// `api-versions.xml`; annotations from class files and `annotations.zip`.
/// When [apiVersions] is provided, symbols absent from it are classified as
/// hidden/non-SDK (`E006`) and never marked supported.
final class AndroidApiExtractor {
  /// Creates an extractor.
  AndroidApiExtractor({
    required this.classes,
    required this.sdkVersion,
    this.apiVersions,
    AnnotationsIndex? annotations,
    this.sourceRevision,
    this.sourceKind = 'sdk',
    this.linkOfficialDocs = true,
  }) : annotations = annotations ?? AnnotationsIndex.empty(),
       _known = classes.classNames.toSet();

  /// Class source.
  final ClassSource classes;

  /// SDK version string for provenance (e.g. `36`).
  final String sdkVersion;

  /// Platform package revision.
  final String? sourceRevision;

  /// Official availability list (null for fixtures).
  final ApiVersionsIndex? apiVersions;

  /// External annotations.
  final AnnotationsIndex annotations;

  /// Provenance source kind.
  final String sourceKind;

  /// Whether to attach developer.android.com reference links.
  final bool linkOfficialDocs;

  final Set<String> _known;
  final _cache = <String, ApiType?>{};
  final _diagnostics = <Diagnostic>[];

  /// Resolves a binary or source-style name (`android.os.Handler.Callback`)
  /// to a known binary name.
  String? resolveClassName(String name) {
    if (_known.contains(name)) return name;
    var candidate = name;
    while (true) {
      final i = candidate.lastIndexOf('.');
      if (i < 0) return null;
      candidate = '${candidate.substring(0, i)}\$${candidate.substring(i + 1)}';
      if (_known.contains(candidate)) return candidate;
    }
  }

  /// Loads one type (cached). Returns null if absent, non-public or invalid.
  ApiType? loadType(String binaryName) {
    if (_cache.containsKey(binaryName)) return _cache[binaryName];
    ApiType? t;
    try {
      final bytes = classes.read(binaryName);
      if (bytes != null) t = _buildType(ClassFile.parse(bytes));
    } on MalformedInputException catch (e) {
      _diagnostics.add(
        Diagnostic(
          DiagnosticCode.invalidAst,
          'Cannot parse class file: ${e.message}',
          severity: Severity.error,
          symbolId: binaryName,
        ),
      );
    }
    return _cache[binaryName] = t;
  }

  /// Extracts the closure described by [request].
  ExtractionResult extract(ExtractionRequest request) {
    final roots0 = <String>{};
    final entryRoots = <String>{};
    for (final pkg in request.packages) {
      final prefix = '$pkg.';
      final matches = classes.classNames.where(
        (c) =>
            c.startsWith(prefix) && !c.substring(prefix.length).contains('.'),
      );
      if (matches.isEmpty) {
        _diagnostics.add(
          Diagnostic(
            DiagnosticCode.sdkNotFound,
            'Package $pkg not found in ${classes.artifactName}',
            severity: Severity.error,
          ),
        );
      }
      roots0.addAll(matches);
    }
    void resolveInto(String name, Set<String> into) {
      final r = resolveClassName(name);
      if (r == null) {
        _diagnostics.add(
          Diagnostic(
            DiagnosticCode.sdkNotFound,
            'Class $name not found in ${classes.artifactName}',
            severity: Severity.error,
            symbolId: name,
          ),
        );
      } else {
        into.add(r);
      }
    }

    for (var c in request.classes) {
      resolveInto(c, roots0);
    }
    for (var c in request.entries) {
      resolveInto(c, entryRoots);
    }

    Iterable<String> neighbors(String id) {
      final t = loadType(id);
      if (t == null) return const [];
      return referencedTypeIds(t).where(_known.contains);
    }

    final depth = SplayTreeMap<String, int>();
    for (final r in roots0) {
      depth[r] = 0;
    }
    computeClosure(entryRoots, neighbors, maxDepth: request.depth).forEach((
      k,
      v,
    ) {
      depth[k] = depth.containsKey(k) ? (v < depth[k]! ? v : depth[k]!) : v;
    });

    // Ancestors are always required: generated types mirror inheritance.
    final queue = Queue<String>.of(depth.keys);
    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      final t = loadType(id);
      if (t == null) continue;
      for (final s in [?t.superClass, ...t.interfaces]) {
        final sid = (s as DeclaredTypeRef).name;
        if (_known.contains(sid) && !depth.containsKey(sid)) {
          depth[sid] = depth[id]! + 1;
          queue.add(sid);
        }
      }
    }

    final types = <ApiType>[];
    for (final id in depth.keys) {
      final t = loadType(id);
      if (t != null) types.add(t);
    }
    _diagnostics.addAll(annotations.diagnostics);
    final diags = _diagnostics.toSet().toList()..sort();
    final module = ApiModule(
      platform: ApiPlatform.android,
      sdkVersion: sdkVersion,
      sourceRevision: sourceRevision,
      generatorVersion: ProjectInfo.generatorVersion,
      types: types,
      diagnostics: diags,
    );
    return ExtractionResult(module, depth, diags);
  }

  // ---------------------------------------------------------------------------

  ApiType? _buildType(ClassFile cf) {
    final id = binaryName(cf.name);
    final inner = cf.selfInnerEntry;
    if (inner != null && (inner.outer == null || inner.simpleName == null)) {
      return null; // local or anonymous class
    }
    final flags = cf.effectiveFlags;
    if (flags & (AccessFlags.public | AccessFlags.protected) == 0) return null;
    if (cf.has(AccessFlags.synthetic)) return null;

    final slash = cf.name.lastIndexOf('/');
    final namespace = slash < 0
        ? ''
        : cf.name.substring(0, slash).replaceAll('/', '.');
    final simpleName = inner?.simpleName ?? cf.name.substring(slash + 1);
    final enclosing = inner?.outer == null ? null : binaryName(inner!.outer!);

    final versions = apiVersions?.classes[id];
    final hidden = apiVersions != null && versions == null;
    final diags = <Diagnostic>[];
    if (hidden) {
      diags.add(
        Diagnostic(
          DiagnosticCode.nonSdkApi,
          'Not listed in api-versions.xml (not part of the public SDK API)',
          symbolId: id,
        ),
      );
    }

    final kind = cf.has(AccessFlags.annotation)
        ? TypeKind.annotationType
        : cf.has(AccessFlags.interface)
        ? TypeKind.interfaceType
        : cf.has(AccessFlags.enum_)
        ? TypeKind.enumType
        : cf.isRecord
        ? TypeKind.recordType
        : TypeKind.classType;

    var typeParameters = const <TypeParameter>[];
    TypeRef? superClass = cf.superName == null
        ? null
        : DeclaredTypeRef(binaryName(cf.superName!));
    var interfaces = [
      for (final i in cf.interfaces) DeclaredTypeRef(binaryName(i)),
    ];
    if (cf.signature != null) {
      try {
        final s = SignatureParser.classSignature(cf.signature!);
        typeParameters = s.typeParameters;
        superClass = cf.superName == null ? null : s.superClass;
        interfaces = s.interfaces.cast<DeclaredTypeRef>();
      } on MalformedInputException catch (e) {
        diags.add(
          Diagnostic(
            DiagnosticCode.invalidAst,
            'Bad class signature: ${e.message}',
            symbolId: id,
          ),
        );
      }
    }
    if (kind == TypeKind.interfaceType || kind == TypeKind.annotationType) {
      superClass = null;
    }

    final typeAnns = _annotations(
      cf.visibleAnnotations,
      cf.invisibleAnnotations,
      annotations.lookup(namespace, id),
    );
    if (cf.deprecated &&
        !typeAnns.any((a) => a.type == 'java.lang.Deprecated')) {
      typeAnns.add(
        const ApiAnnotation(
          'java.lang.Deprecated',
          classification: AnnotationClassification.semantic,
        ),
      );
    }
    final classThreading = threadingOf(typeAnns) ?? Threading.unspecified;

    final nested = <String>[
      for (final e in cf.innerClasses)
        if (e.outer == cf.name &&
            e.simpleName != null &&
            e.flags & (AccessFlags.public | AccessFlags.protected) != 0)
          binaryName(e.inner),
    ]..sort();

    final supers = [
      if (cf.superName != null) binaryName(cf.superName!),
      ...cf.interfaces.map(binaryName),
    ];
    var fields = <ApiField>[
      for (final f in cf.fields)
        if (_isApiMember(f)) _buildField(id, namespace, f, versions, supers),
    ];
    var methods = <ApiMethod>[
      for (final m in cf.methods)
        if (_isApiMember(m) &&
            m.name != '<clinit>' &&
            !m.has(AccessFlags.volatileOrBridge))
          _buildMethod(
            id,
            namespace,
            simpleName,
            cf,
            m,
            versions,
            classThreading,
          ),
    ];

    if (hidden) {
      // Members of a non-SDK type are non-SDK as well.
      Diagnostic why(String mid) => Diagnostic(
        DiagnosticCode.nonSdkApi,
        'Declared in non-SDK type $id',
        symbolId: mid,
      );
      fields = [
        for (final f in fields)
          ApiField(
            id: f.id,
            name: f.name,
            type: f.type,
            constantValue: f.constantValue,
            nativeDescriptor: f.nativeDescriptor,
            modifiers: f.modifiers,
            annotations: f.annotations,
            availability: f.availability,
            visibility: ApiVisibility.hiddenOrNonSdk,
            support: SupportStatus.unsupported,
            documentation: f.documentation,
            diagnostics: [why(f.id)],
          ),
      ];
      methods = [
        for (final m in methods)
          ApiMethod(
            id: m.id,
            name: m.name,
            kind: m.kind,
            returnType: m.returnType,
            parameters: m.parameters,
            typeParameters: m.typeParameters,
            throws: m.throws,
            threading: m.threading,
            permissions: m.permissions,
            nativeDescriptor: m.nativeDescriptor,
            modifiers: m.modifiers,
            annotations: m.annotations,
            availability: m.availability,
            visibility: ApiVisibility.hiddenOrNonSdk,
            support: SupportStatus.unsupported,
            documentation: m.documentation,
            diagnostics: [why(m.id)],
          ),
      ];
    }

    final mods = _modifiers(flags, isMethod: false);
    if (kind == TypeKind.interfaceType) mods.remove(Modifier.abstract_);
    return ApiType(
      id: id,
      name: simpleName,
      kind: kind,
      namespace: namespace,
      provenance: Provenance(
        platform: ApiPlatform.android,
        sourceKind: sourceKind,
        sdkVersion: sdkVersion,
        localArtifact: classes.artifactName,
        artifactEntry: '${cf.name}.class',
        officialReference: _docLink(id, namespace),
      ),
      typeParameters: typeParameters,
      superClass: superClass,
      interfaces: interfaces,
      enclosingType: enclosing,
      nestedTypes: nested,
      fields: fields,
      methods: methods,
      threading: classThreading,
      modifiers: mods,
      annotations: typeAnns..sort(),
      availability: versions?.info.toAvailability() ?? Availability.unknown,
      visibility: hidden ? ApiVisibility.hiddenOrNonSdk : ApiVisibility.public,
      support: hidden ? SupportStatus.unsupported : SupportStatus.supported,
      documentation: _docs(_docLink(id, namespace)),
      diagnostics: diags,
    );
  }

  bool _isApiMember(MemberInfo m) =>
      m.has(AccessFlags.public | AccessFlags.protected) &&
      !m.has(AccessFlags.synthetic);

  ApiField _buildField(
    String owner,
    String ns,
    MemberInfo f,
    ClassVersions? versions,
    List<String> supers,
  ) {
    final id = SymbolIds.field(owner, f.name);
    final diags = <Diagnostic>[];
    TypeRef type;
    try {
      type = SignatureParser.fieldType(f.signature ?? f.descriptor);
    } on MalformedInputException catch (e) {
      diags.add(
        Diagnostic(
          DiagnosticCode.invalidAst,
          'Bad field signature: ${e.message}',
          symbolId: id,
        ),
      );
      type = SignatureParser.fieldType(f.descriptor);
    }
    final anns = _annotations(
      f.visibleAnnotations,
      f.invisibleAnnotations,
      annotations.lookup(ns, id),
    );
    if (f.deprecated && !anns.any((a) => a.type == 'java.lang.Deprecated')) {
      anns.add(
        const ApiAnnotation(
          'java.lang.Deprecated',
          classification: AnnotationClassification.semantic,
        ),
      );
    }
    final v = versions == null
        ? null
        : apiVersions!.field(owner, f.name, extraSupertypes: supers);
    final unlisted = versions != null && v == null;
    if (unlisted) diags.add(_unlisted(id));
    // Constant fields are never null.
    final isConst = f.constantValue != null;
    return ApiField(
      id: id,
      name: f.name,
      type: _withNullability(
        type,
        isConst ? Nullability.nonnull : nullabilityOf(anns),
      ),
      constantValue: isConst ? _constant(f, type) : null,
      nativeDescriptor: f.descriptor,
      modifiers: _modifiers(f.accessFlags, isMethod: false),
      annotations: anns..sort(),
      availability:
          v?.toAvailability(versions!.info) ??
          versions?.info.toAvailability() ??
          Availability.unknown,
      support: unlisted ? SupportStatus.partial : SupportStatus.supported,
      documentation: _docs(_docLink(owner, ns, member: f.name)),
      diagnostics: diags,
    );
  }

  ApiMethod _buildMethod(
    String owner,
    String ns,
    String ownerSimple,
    ClassFile cf,
    MemberInfo m,
    ClassVersions? versions,
    Threading classThreading,
  ) {
    final isCtor = m.name == '<init>';
    final erased = SignatureParser.method(m.descriptor);
    final id = SymbolIds.method(owner, m.name, erased.parameters);
    final diags = <Diagnostic>[];
    var sig = erased;
    if (m.signature != null) {
      try {
        final g = SignatureParser.method(m.signature!);
        if (g.parameters.length == erased.parameters.length) {
          sig = g;
        } else {
          // Inner-class / enum constructors carry implicit parameters that
          // the generic signature omits; the descriptor is authoritative.
          sig = MethodSignature(
            g.typeParameters,
            erased.parameters,
            erased.returnType,
            g.throws,
          );
          diags.add(
            Diagnostic(
              DiagnosticCode.unsupportedGeneric,
              'Generic signature omits implicit parameters; using erased descriptor types',
              severity: Severity.info,
              symbolId: id,
            ),
          );
        }
      } on MalformedInputException catch (e) {
        diags.add(
          Diagnostic(
            DiagnosticCode.invalidAst,
            'Bad method signature: ${e.message}',
            symbolId: id,
          ),
        );
      }
    }

    final anns = _annotations(
      m.visibleAnnotations,
      m.invisibleAnnotations,
      annotations.lookup(ns, id),
    );
    if (m.deprecated && !anns.any((a) => a.type == 'java.lang.Deprecated')) {
      anns.add(
        const ApiAnnotation(
          'java.lang.Deprecated',
          classification: AnnotationClassification.semantic,
        ),
      );
    }

    final isStatic = m.has(AccessFlags.static_);
    var slot = isStatic ? 0 : 1;
    final params = <ApiParameter>[];
    for (var i = 0; i < sig.parameters.length; i++) {
      final t = sig.parameters[i];
      final pAnns = _annotations(
        m.parameterAnnotationsInvisible[i] == true
            ? const []
            : m.parameterAnnotations[i] ?? const [],
        m.parameterAnnotationsInvisible[i] == true
            ? m.parameterAnnotations[i] ?? const []
            : const [],
        annotations.lookup(ns, '$id@$i'),
      )..sort();
      var name =
          m.methodParameterNames != null && i < m.methodParameterNames!.length
          ? m.methodParameterNames![i]
          : null;
      var nameSource = 'MethodParameters';
      if (name == null) {
        name = m.localVariableNames[slot];
        nameSource = 'LocalVariableTable';
      }
      if (name == null) {
        name = 'p$i';
        nameSource = 'synthesized';
      }
      params.add(
        ApiParameter(
          name,
          _withNullability(t, nullabilityOf(pAnns)),
          annotations: pAnns,
          nameSource: nameSource,
        ),
      );
      final e = erased.parameters[i];
      slot +=
          (e is PrimitiveTypeRef &&
              (e.kind == PrimitiveKind.long || e.kind == PrimitiveKind.double_))
          ? 2
          : 1;
    }

    final throws = sig.throws.isNotEmpty
        ? sig.throws
        : [for (final e in m.exceptions) DeclaredTypeRef(binaryName(e))];

    final v = versions == null
        ? null
        : apiVersions!.method(
            owner,
            m.name,
            m.descriptor,
            extraSupertypes: [
              if (cf.superName != null) binaryName(cf.superName!),
              ...cf.interfaces.map(binaryName),
            ],
          );
    final unlisted = versions != null && v == null;
    if (unlisted) diags.add(_unlisted(id));
    final mods = _modifiers(m.accessFlags, isMethod: true);
    if (cf.has(AccessFlags.interface) &&
        !m.has(AccessFlags.abstract_) &&
        !isStatic) {
      mods.add(Modifier.default_);
    }
    final anchorName = isCtor ? ownerSimple : m.name;
    return ApiMethod(
      id: id,
      name: m.name,
      kind: isCtor ? MethodKind.constructor : MethodKind.method,
      returnType: isCtor
          ? const PrimitiveTypeRef(PrimitiveKind.void_)
          : _withNullability(sig.returnType, nullabilityOf(anns)),
      parameters: params,
      typeParameters: sig.typeParameters,
      throws: throws,
      threading: threadingOf(anns) ?? classThreading,
      permissions: permissionsOf(anns),
      nativeDescriptor: m.descriptor,
      modifiers: mods,
      annotations: anns..sort(),
      availability:
          v?.toAvailability(versions!.info) ??
          versions?.info.toAvailability() ??
          Availability.unknown,
      support: unlisted ? SupportStatus.partial : SupportStatus.supported,
      documentation: _docs(
        _docLink(
          owner,
          ns,
          member:
              '$anchorName(${erased.parameters.map((t) => t.erasedId.replaceAll(r'$', '.')).join(', ')})',
        ),
      ),
      diagnostics: diags,
    );
  }

  // Public stub members that the official list omits: in practice members
  // re-declared from a non-public superclass. They are public API (they are
  // in android.jar), but their availability is inferred, not listed.
  Diagnostic _unlisted(String id) => Diagnostic(
    DiagnosticCode.availabilityMismatch,
    'Not listed in api-versions.xml (inherited from a non-public superclass); '
    'availability inferred from the declaring class',
    severity: Severity.info,
    symbolId: id,
  );

  List<ApiAnnotation> _annotations(
    List<RawAnnotation> visible,
    List<RawAnnotation> invisible,
    List<ExternalAnnotation> external,
  ) {
    final out = <ApiAnnotation>[];
    for (final a in visible) {
      out.add(
        ApiAnnotation(
          a.typeName,
          values: a.values,
          classification: classifyAnnotation(a.typeName, runtimeVisible: true),
          source: 'classfile',
        ),
      );
    }
    for (final a in invisible) {
      out.add(
        ApiAnnotation(
          a.typeName,
          values: a.values,
          classification: classifyAnnotation(a.typeName, runtimeVisible: false),
          source: 'classfile-invisible',
        ),
      );
    }
    for (final a in external) {
      out.add(
        ApiAnnotation(
          a.type,
          values: a.values,
          classification: classifyAnnotation(a.type, runtimeVisible: false),
          source: 'annotations.zip',
        ),
      );
    }
    return out;
  }

  Set<Modifier> _modifiers(int f, {required bool isMethod}) => {
    if (f & AccessFlags.public != 0) Modifier.public,
    if (f & AccessFlags.protected != 0) Modifier.protected,
    if (f & AccessFlags.static_ != 0) Modifier.static_,
    if (f & AccessFlags.final_ != 0) Modifier.final_,
    if (f & AccessFlags.abstract_ != 0) Modifier.abstract_,
    if (isMethod && f & AccessFlags.synchronized != 0) Modifier.synchronized,
    if (isMethod && f & AccessFlags.native != 0) Modifier.native,
    if (isMethod && f & AccessFlags.transientOrVarargs != 0) Modifier.varargs,
    if (!isMethod && f & AccessFlags.volatileOrBridge != 0) Modifier.volatile,
    if (!isMethod && f & AccessFlags.transientOrVarargs != 0)
      Modifier.transient,
  };

  TypeRef _withNullability(TypeRef t, Nullability n) =>
      t is PrimitiveTypeRef ? t : t.withNullability(n);

  ConstantValue _constant(MemberInfo f, TypeRef type) {
    final v = f.constantValue;
    final kind = type is PrimitiveTypeRef ? type.kind.javaName : 'string';
    String lit;
    if (v is double) {
      lit = v.isNaN
          ? 'NaN'
          : v.isInfinite
          ? (v > 0 ? 'Infinity' : '-Infinity')
          : (kind == 'float' ? _floatLiteral(v) : v.toString());
    } else if (kind == 'boolean') {
      lit = v == 1 ? 'true' : 'false';
    } else {
      lit = '$v';
    }
    return ConstantValue(kind, lit);
  }

  // Shortest decimal that round-trips through float32.
  static String _floatLiteral(double v) {
    for (var digits = 1; digits <= 9; digits++) {
      final s = v.toStringAsPrecision(digits);
      final back = Float32List(1)..[0] = double.parse(s);
      if (back[0] == v) return double.parse(s).toString();
    }
    return v.toString();
  }

  String? _docLink(String id, String ns, {String? member}) {
    if (!linkOfficialDocs) return null;
    final path =
        '${ns.replaceAll('.', '/')}/${id.substring(ns.length + 1).replaceAll(r'$', '.')}';
    return 'https://developer.android.com/reference/$path${member == null ? '' : '#$member'}';
  }

  Documentation _docs(String? link) => link == null
      ? const Documentation()
      : Documentation(sourceType: 'link', reference: link);
}
