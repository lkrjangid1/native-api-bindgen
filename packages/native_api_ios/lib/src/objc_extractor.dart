import 'dart:collection';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;

import 'libclang.dart';

/// What to extract from Apple headers.
final class ObjCRequest {
  /// Creates a request.
  const ObjCRequest({
    this.frameworks = const [],
    this.classes = const [],
    this.entries = const [],
    this.depth = 1,
  });

  /// Frameworks to generate entirely (e.g. `UIKit`).
  final List<String> frameworks;

  /// Individual types (`UIKit.UIView` or `UIView`).
  final List<String> classes;

  /// Dependency-aware roots.
  final List<String> entries;

  /// Dependency depth from [entries].
  final int depth;
}

/// Raw declaration collected from the translation unit before IR building.
final class _Decl {
  _Decl(this.kind, this.name, this.module, this.isPrivate, this.cursor);

  final int kind;
  final String name;
  final String module;
  final bool isPrivate;
  final CXCursor cursor;
  final categories = <CXCursor>[];
}

/// Extracts Objective-C APIs from Apple SDK headers (or synthetic fixture
/// headers) through libclang into Native IR (TRD §20–§23).
///
/// Signatures, nullability and per-platform availability come from the
/// headers via libclang; documentation is only linked, never copied.
final class ObjCExtractor {
  /// Creates an extractor.
  ///
  /// [sysroot]/[target] select the SDK (e.g. iphonesimulator,
  /// `arm64-apple-ios13.0-simulator`). [moduleForPath] maps headers that are
  /// not inside a `.framework` (fixtures) to a module name.
  ObjCExtractor({
    required String libclangPath,
    required this.sysroot,
    required this.target,
    required this.sdkVersion,
    this.sourceKind = 'headers',
    this.fixtureModule,
    this.linkOfficialDocs = true,
    this.fixtureArtifact = 'fixture headers',
  }) : _clang = LibClang(libclangPath);

  final LibClang _clang;

  /// SDK root used as `-isysroot`.
  final String sysroot;

  /// Clang target triple.
  final String target;

  /// SDK version for provenance.
  final String sdkVersion;

  /// Provenance source kind.
  final String sourceKind;

  /// Module name for non-framework headers (fixtures), or null to ignore them.
  final String? fixtureModule;

  /// Whether to attach developer.apple.com links.
  final bool linkOfficialDocs;

  /// Provenance artifact recorded for [fixtureModule] declarations.
  final String fixtureArtifact;

  final _decls = <String, _Decl>{}; // id -> decl
  final _byName =
      <String, String>{}; // ObjC class/protocol/enum/struct name -> id
  final _protocolByName = <String, String>{};
  final _diagnostics = <Diagnostic>[];
  final _cache = <String, ApiType?>{};
  final _typedefs = <String, CXCursor>{};
  final _fixtureDirs = <String>{};
  final _tagAlias = <String, String>{}; // struct/enum tag -> typedef name
  late String _currentType;

  static final _frameworkRe = RegExp(
    r'/([A-Za-z0-9_]+)\.framework/(?:Versions/[^/]+/)?(Headers|PrivateHeaders)/',
  );

  /// Parses [headers] (absolute paths, or `<Framework/Framework.h>`
  /// imports) and indexes their declarations.
  void parse(List<String> imports, {List<String> headerFiles = const []}) {
    for (final h in headerFiles) {
      _fixtureDirs.add(p.dirname(p.normalize(p.absolute(h))));
    }
    final umbrella = File(
      p.join(
        Directory.systemTemp.createTempSync('nab_objc').path,
        'umbrella.m',
      ),
    );
    umbrella.writeAsStringSync(
      [
        for (final i in imports) '#import <$i>',
        for (final h in headerFiles) '#import "${h.replaceAll('"', r'\"')}"',
      ].join('\n'),
    );
    final argv = [
      '-x',
      'objective-c',
      '-isysroot',
      sysroot,
      '-target',
      target,
      '-fobjc-arc',
      '-Wno-everything',
    ];
    final cargs = calloc<Pointer<Char>>(argv.length);
    final idx = _clang.createIndex(0, 0);
    try {
      for (var i = 0; i < argv.length; i++) {
        cargs[i] = argv[i].toNativeUtf8().cast();
      }
      // SkipFunctionBodies | IncludeAttributedTypes | VisitImplicitAttributes
      final tu = _clang.parseTranslationUnit(
        idx,
        umbrella.path.toNativeUtf8().cast(),
        cargs,
        argv.length,
        nullptr,
        0,
        64 | 0x1000 | 0x2000,
      );
      if (tu == nullptr) {
        throw StateError('libclang could not parse the headers');
      }
      for (var i = 0; i < _clang.getNumDiagnostics(tu); i++) {
        final d = _clang.getDiagnostic(tu, i);
        if (_clang.getDiagnosticSeverity(d) >= 3) {
          _diagnostics.add(
            Diagnostic(
              DiagnosticCode.invalidAst,
              'Header error: ${_clang.str(_clang.getDiagnosticSpelling(d))}',
              severity: Severity.error,
            ),
          );
        }
        _clang.disposeDiagnostic(d);
      }
      _index(_clang.getTranslationUnitCursor(tu));
      // Note: the translation unit is intentionally kept alive (cursors
      // reference it) for the lifetime of this extractor.
    } finally {
      for (var i = 0; i < argv.length; i++) {
        calloc.free(cargs[i]);
      }
      calloc.free(cargs);
      try {
        umbrella.parent.deleteSync(recursive: true);
      } on FileSystemException {
        // best effort
      }
    }
  }

  (String?, bool) _moduleOf(CXCursor c) {
    final file = _clang.fileOf(c);
    final m = _frameworkRe.firstMatch(file);
    if (m != null) return (m[1], m[2] == 'PrivateHeaders');
    // The Objective-C runtime (NSObject, <NSObject>) is the `ObjectiveC` module.
    if (file.startsWith(sysroot) && file.contains('/usr/include/objc/')) {
      return ('ObjectiveC', false);
    }
    if (fixtureModule != null && _fixtureDirs.any((d) => p.isWithin(d, file))) {
      return (fixtureModule, false);
    }
    return (null, false);
  }

  void _index(CXCursor root) {
    final categories = <(String, CXCursor)>[];
    final protocols = <String, _Decl>{};
    for (final c in _clang.children(root)) {
      final kind = _clang.getCursorKind(c);
      if (kind == CursorKind.typedefDecl) {
        final tdName = _clang.str(_clang.getCursorSpelling(c));
        _typedefs[tdName] = c;
        // `typedef enum {...} Name;` and `typedef struct _Name {...} Name;`:
        // the typedef name is the public identity of the value type.
        final under = _clang.getCanonicalType(_clang.typedefUnderlying(c));
        if (under.kind == TypeKindC.enum_ || under.kind == TypeKindC.record) {
          final decl = _clang.getTypeDeclaration(under);
          final declName = _clang.str(_clang.getCursorSpelling(decl));
          final (module, isPrivate) = _moduleOf(decl);
          if (module != null &&
              _clang.children(decl).isNotEmpty &&
              !tdName.startsWith('_') &&
              (declName.isEmpty ||
                  declName.contains(' ') ||
                  declName.startsWith('_'))) {
            final id = '$module.$tdName';
            if (!_decls.containsKey(id)) {
              _decls[id] = _Decl(
                _clang.getCursorKind(decl),
                tdName,
                module,
                isPrivate,
                decl,
              );
              _byName[tdName] = id;
              _tagAlias[declName] = tdName;
            }
          }
        }
        continue;
      }
      if (kind != CursorKind.objcInterfaceDecl &&
          kind != CursorKind.objcProtocolDecl &&
          kind != CursorKind.objcCategoryDecl &&
          kind != CursorKind.enumDecl &&
          kind != CursorKind.structDecl) {
        continue;
      }
      final name = _clang.str(_clang.getCursorSpelling(c));
      // Anonymous declarations are reached through their typedef.
      if (name.isEmpty || name.contains(' ') || _tagAlias.containsKey(name)) {
        continue;
      }
      if (kind == CursorKind.objcCategoryDecl) {
        final ref = _clang
            .children(c)
            .where((x) => _clang.getCursorKind(x) == CursorKind.objcClassRef)
            .firstOrNull;
        if (ref != null) {
          categories.add((_clang.str(_clang.getCursorSpelling(ref)), c));
        }
        continue;
      }
      // Only definitions: skip `@class X;` / `@protocol P;` forward
      // declarations. For interfaces libclang's definition is the
      // @implementation (absent in SDK headers), so a declaration with
      // members (or a superclass) counts as the definition.
      if (kind == CursorKind.objcInterfaceDecl) {
        if (_clang.children(c).isEmpty) continue;
      } else {
        final def = _clang.getCursorDefinition(c);
        if (_clang.cursorIsNull(def) != 0 || _clang.equalCursors(def, c) == 0) {
          continue;
        }
      }
      final (module, isPrivate) = _moduleOf(c);
      if (module == null) continue;
      final isProtocol = kind == CursorKind.objcProtocolDecl;
      final decl = _Decl(
        kind,
        name,
        module,
        isPrivate || name.startsWith('_'),
        c,
      );
      if (isProtocol) {
        protocols[name] = decl;
      } else {
        final id = '$module.$name';
        _byName[name] = id;
        _decls[id] = decl;
      }
    }
    // Classes and protocols live in separate ObjC namespaces (NSObject vs
    // <NSObject>); protocols get a `Protocol` suffix when a class shares the
    // name (as package:objective_c does for NSObjectProtocol).
    for (final e in protocols.entries) {
      final d = e.value;
      final id = _byName.containsKey(e.key)
          ? '${d.module}.${d.name}Protocol'
          : '${d.module}.${d.name}';
      _protocolByName[e.key] = id;
      _decls[id] = d;
    }
    for (final (cls, cat) in categories) {
      final id = _byName[cls];
      if (id != null) _decls[id]?.categories.add(cat);
    }
  }

  /// All indexed type IDs.
  Iterable<String> get typeIds => _decls.keys;

  /// Resolves `UIKit.UIView` / `UIView` to an indexed ID.
  String? resolve(String name) {
    if (_decls.containsKey(name)) return name;
    final simple = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1)
        : name;
    return _byName[simple] ?? _protocolByName[simple];
  }

  /// Builds (cached) the IR type for [id].
  ApiType? loadType(String id) {
    if (_cache.containsKey(id)) return _cache[id];
    final d = _decls[id];
    ApiType? t;
    if (d != null) {
      _currentType = id;
      t = switch (d.kind) {
        CursorKind.objcInterfaceDecl ||
        CursorKind.objcProtocolDecl => _buildClass(id, d),
        CursorKind.enumDecl => _buildEnum(id, d),
        CursorKind.structDecl => _buildStruct(id, d),
        _ => null,
      };
    }
    return _cache[id] = t;
  }

  /// Extracts the closure described by [request].
  ApiModule extract(ObjCRequest request) {
    final roots0 = <String>{};
    final entryRoots = <String>{};
    for (final fw in request.frameworks) {
      final ids = _decls.keys.where((k) => _decls[k]!.module == fw);
      if (ids.isEmpty) {
        _diagnostics.add(
          Diagnostic(
            DiagnosticCode.sdkNotFound,
            'Framework $fw not found or empty',
            severity: Severity.error,
          ),
        );
      }
      roots0.addAll(ids);
    }
    void into(String n, Set<String> s) {
      final r = resolve(n);
      if (r == null) {
        _diagnostics.add(
          Diagnostic(
            DiagnosticCode.sdkNotFound,
            'Type $n not found in the parsed headers',
            severity: Severity.error,
            symbolId: n,
          ),
        );
      } else {
        s.add(r);
      }
    }

    for (var c in request.classes) {
      into(c, roots0);
    }
    for (var c in request.entries) {
      into(c, entryRoots);
    }
    Iterable<String> neighbors(String id) {
      final t = loadType(id);
      return t == null
          ? const []
          : referencedTypeIds(t).where(_decls.containsKey);
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
    // Ancestors (superclasses + adopted protocols) are always included.
    final queue = Queue<String>.of(depth.keys);
    while (queue.isNotEmpty) {
      final t = loadType(queue.removeFirst());
      if (t == null) continue;
      for (final s in [?t.superClass, ...t.interfaces]) {
        final sid = (s as DeclaredTypeRef).name;
        if (_decls.containsKey(sid) && !depth.containsKey(sid)) {
          depth[sid] = depth[t.id]! + 1;
          queue.add(sid);
        }
      }
    }
    // Value types (structs, enums) used by included signatures are always
    // needed to call those members, whatever their module or depth.
    final valueQueue = Queue<String>.of(depth.keys);
    while (valueQueue.isNotEmpty) {
      final t = loadType(valueQueue.removeFirst());
      if (t == null) continue;
      for (final ref in referencedTypeIds(t)) {
        final kind = _decls[ref]?.kind;
        if ((kind == CursorKind.structDecl || kind == CursorKind.enumDecl) &&
            !depth.containsKey(ref)) {
          depth[ref] = (depth[t.id] ?? 0) + 1;
          valueQueue.add(ref);
        }
      }
      for (final f in t.fields) {
        for (final ref in f.type.referencedTypes) {
          final kind = _decls[ref]?.kind;
          if ((kind == CursorKind.structDecl || kind == CursorKind.enumDecl) &&
              !depth.containsKey(ref)) {
            depth[ref] = (depth[t.id] ?? 0) + 1;
            valueQueue.add(ref);
          }
        }
      }
    }
    return ApiModule(
      platform: ApiPlatform.apple,
      sdkVersion: sdkVersion,
      generatorVersion: ProjectInfo.generatorVersion,
      types: [for (final id in depth.keys) ?loadType(id)],
      diagnostics: _diagnostics.toSet().toList()..sort(),
    );
  }

  // ------------------------------------------------------------------ build

  Provenance _provenance(_Decl d) => Provenance(
    platform: ApiPlatform.apple,
    sourceKind: sourceKind,
    sdkVersion: sdkVersion,
    localArtifact: d.module == fixtureModule
        ? fixtureArtifact
        : '${d.module}.framework',
    artifactEntry: p.basename(_clang.fileOf(d.cursor)),
    officialReference: _docLink(d),
  );

  String? _docLink(_Decl d) => !linkOfficialDocs || d.module == fixtureModule
      ? null
      : 'https://developer.apple.com/documentation/${d.module.toLowerCase()}/${d.name.toLowerCase()}';

  Availability _availability(CXCursor c) {
    final arr = calloc<CXPlatformAvailability>(16);
    final alwaysDeprecated = calloc<Int>();
    final alwaysUnavailable = calloc<Int>();
    try {
      final n = _clang.platformAvailability(
        c,
        alwaysDeprecated,
        nullptr,
        alwaysUnavailable,
        nullptr,
        arr,
        16,
      );
      ApiVersion? v(CXVersion x) => x.major < 0
          ? null
          : ApiVersion(
              x.major,
              x.minor < 0 ? 0 : x.minor,
              x.subminor < 0 ? 0 : x.subminor,
            );
      final platforms = <String, PlatformAvailability>{};
      for (var i = 0; i < n && i < 16; i++) {
        final a = arr[i];
        final name = _clang.str(a.platform);
        _clang.str(a.message);
        platforms[name] = PlatformAvailability(
          introduced: v(a.introduced),
          deprecated: v(a.deprecated),
          obsoleted: v(a.obsoleted),
          unavailable: a.unavailable != 0 || alwaysUnavailable.value != 0,
        );
      }
      final ios = platforms['ios'];
      return Availability(
        introduced: ios?.introduced,
        deprecated:
            ios?.deprecated ??
            (alwaysDeprecated.value != 0 ? const ApiVersion(0) : null),
        removed: ios?.obsoleted,
        platforms: platforms,
      );
    } finally {
      calloc.free(arr);
      calloc.free(alwaysDeprecated);
      calloc.free(alwaysUnavailable);
    }
  }

  Availability _inherit(Availability member, Availability owner) {
    if (member.platforms.isNotEmpty) return member;
    return owner;
  }

  List<Diagnostic> _availabilityDiags(
    String id,
    Availability a,
    bool isPrivate,
  ) => [
    if (isPrivate)
      Diagnostic(
        DiagnosticCode.privateApi,
        'Private or SPI declaration (not public SDK API)',
        symbolId: id,
      ),
    if (a.platforms['ios']?.unavailable ?? false)
      Diagnostic(
        DiagnosticCode.availabilityMismatch,
        'Unavailable on iOS',
        symbolId: id,
      ),
  ];

  ApiType _buildClass(String id, _Decl d) {
    final isProtocol = d.kind == CursorKind.objcProtocolDecl;
    final availability = _availability(d.cursor);
    TypeRef? superClass;
    final interfaces = <TypeRef>[];
    final methods = <ApiMethod>[];
    final properties = <ApiProperty>[];
    final seen = <String>{};
    final diags = <Diagnostic>[
      ..._availabilityDiags(id, availability, d.isPrivate),
    ];
    if (d.categories.isNotEmpty) {
      // Categories from other frameworks are merged into the class.
    }
    for (final container in [d.cursor, ...d.categories]) {
      for (final c in _clang.children(container)) {
        final kind = _clang.getCursorKind(c);
        switch (kind) {
          case CursorKind.objcSuperClassRef:
            final sid = _byName[_clang.str(_clang.getCursorSpelling(c))];
            if (sid != null) superClass = DeclaredTypeRef(sid);
          case CursorKind.objcProtocolRef:
            final pid =
                _protocolByName[_clang.str(_clang.getCursorSpelling(c))];
            if (pid != null &&
                !interfaces.any((i) => (i as DeclaredTypeRef).name == pid)) {
              interfaces.add(DeclaredTypeRef(pid));
            }
          case CursorKind.objcInstanceMethodDecl ||
              CursorKind.objcClassMethodDecl:
            final m = _buildMethod(
              id,
              c,
              kind == CursorKind.objcClassMethodDecl,
              availability,
              isProtocol,
            );
            if (seen.add(m.id)) methods.add(m);
          case CursorKind.objcPropertyDecl:
            final prop = _buildProperty(id, c);
            if (prop != null) properties.add(prop);
        }
      }
    }
    final mods = <Modifier>{Modifier.public};
    return ApiType(
      id: id,
      name: d.name,
      kind: isProtocol ? TypeKind.protocol : TypeKind.classType,
      namespace: d.module,
      provenance: _provenance(d),
      superClass: superClass,
      interfaces: interfaces,
      methods: methods,
      properties: properties,
      modifiers: mods,
      availability: availability,
      visibility: d.isPrivate ? ApiVisibility.private : ApiVisibility.public,
      support: diags.isEmpty
          ? SupportStatus.supported
          : SupportStatus.unsupported,
      documentation: _docLink(d) == null
          ? const Documentation()
          : Documentation(sourceType: 'link', reference: _docLink(d)),
      diagnostics: diags,
    );
  }

  static bool _isInitFamily(String selector) =>
      selector == 'init' ||
      (selector.startsWith('init') &&
          selector.length > 4 &&
          selector[4].toUpperCase() == selector[4] &&
          selector[4] != '_');

  ApiMethod _buildMethod(
    String owner,
    CXCursor c,
    bool isClass,
    Availability ownerAvailability,
    bool inProtocol,
  ) {
    final selector = _clang.str(_clang.getCursorSpelling(c));
    final id = '$owner#${isClass ? '+' : '-'}$selector';
    final ret = _type(_clang.getCursorResultType(c));
    final params = <ApiParameter>[];
    final diags = <Diagnostic>[];
    for (var i = 0; i < _clang.getNumArguments(c); i++) {
      final a = _clang.getArgument(c, i);
      params.add(
        ApiParameter(
          _clang.str(_clang.getCursorSpelling(a)),
          _type(_clang.getCursorType(a)),
          nameSource: 'header',
        ),
      );
    }
    final availability = _inherit(_availability(c), ownerAvailability);
    diags.addAll(
      _availabilityDiags(id, availability, selector.startsWith('_')),
    );
    if (_clang.isVariadic(c) != 0) {
      diags.add(
        Diagnostic(
          DiagnosticCode.unsupportedType,
          'Variadic Objective-C methods are not supported',
          symbolId: id,
        ),
      );
    }
    final private = selector.startsWith('_');
    final unsupported = diags.any(
      (d) =>
          d.code == DiagnosticCode.unsupportedType ||
          d.code == DiagnosticCode.availabilityMismatch,
    );
    final isInit = !isClass && _isInitFamily(selector);
    return ApiMethod(
      id: id,
      name: selector,
      kind: isInit ? MethodKind.constructor : MethodKind.method,
      returnType: ret,
      parameters: params,
      nativeDescriptor: selector,
      modifiers: {
        Modifier.public,
        if (isClass) Modifier.static_,
        if (inProtocol && _clang.isObjCOptional(c) == 0) Modifier.abstract_,
      },
      annotations: [
        if (inProtocol && _clang.isObjCOptional(c) != 0)
          const ApiAnnotation(
            'objc.optional',
            classification: AnnotationClassification.semantic,
            source: 'headers',
          ),
      ],
      availability: availability,
      visibility: private ? ApiVisibility.private : ApiVisibility.public,
      support: private || unsupported
          ? SupportStatus.unsupported
          : SupportStatus.supported,
      diagnostics: diags,
    );
  }

  ApiProperty? _buildProperty(String owner, CXCursor c) {
    final name = _clang.str(_clang.getCursorSpelling(c));
    final attrs = _clang.propertyAttributes(c, 0);
    final isClass = attrs & PropertyAttr.class_ != 0;
    var getter = _clang.str(_clang.propertyGetterName(c));
    if (getter.isEmpty) getter = name;
    var setter = _clang.str(_clang.propertySetterName(c));
    if (setter.isEmpty) {
      setter = 'set${name[0].toUpperCase()}${name.substring(1)}:';
    }
    final sign = isClass ? '+' : '-';
    final readonly = attrs & PropertyAttr.readonly != 0;
    return ApiProperty(
      name: name,
      type: _type(_clang.getCursorType(c)),
      getterId: '$owner#$sign$getter',
      setterId: readonly ? null : '$owner#$sign$setter',
      backing: 'accessor',
    );
  }

  ApiType? _buildEnum(String id, _Decl d) {
    final fields = <ApiField>[];
    final intType = _type(_clang.enumIntegerType(d.cursor));
    final unsigned =
        intType is PrimitiveTypeRef &&
        const {
          PrimitiveKind.uint8,
          PrimitiveKind.uint16,
          PrimitiveKind.uint32,
          PrimitiveKind.uint64,
        }.contains(intType.kind);
    final enumAvailability = _availability(d.cursor);
    for (final c in _clang.children(d.cursor)) {
      if (_clang.getCursorKind(c) != CursorKind.enumConstantDecl) continue;
      final n = _clang.str(_clang.getCursorSpelling(c));
      final value = unsigned
          ? BigInt.from(
              _clang.enumConstantUnsignedValue(c),
            ).toUnsigned(64).toString()
          : '${_clang.enumConstantValue(c)}';
      final fid = '$id#$n';
      final availability = _inherit(_availability(c), enumAvailability);
      final diags = _availabilityDiags(fid, availability, n.startsWith('_'));
      fields.add(
        ApiField(
          id: fid,
          name: n,
          type: intType,
          constantValue: ConstantValue(
            intType is PrimitiveTypeRef ? intType.kind.javaName : 'long',
            value,
          ),
          modifiers: const {Modifier.public, Modifier.static_, Modifier.final_},
          availability: availability,
          support: diags.isEmpty
              ? SupportStatus.supported
              : SupportStatus.unsupported,
          visibility: n.startsWith('_')
              ? ApiVisibility.private
              : ApiVisibility.public,
          diagnostics: diags,
        ),
      );
    }
    return ApiType(
      id: id,
      name: d.name,
      kind: TypeKind.enumType,
      namespace: d.module,
      provenance: _provenance(d),
      fields: fields,
      modifiers: const {Modifier.public},
      availability: enumAvailability,
      visibility: d.isPrivate ? ApiVisibility.private : ApiVisibility.public,
      support: d.isPrivate
          ? SupportStatus.unsupported
          : SupportStatus.supported,
      diagnostics: _availabilityDiags(id, enumAvailability, d.isPrivate),
      documentation: _docLink(d) == null
          ? const Documentation()
          : Documentation(sourceType: 'link', reference: _docLink(d)),
    );
  }

  ApiType? _buildStruct(String id, _Decl d) {
    final fields = <ApiField>[];
    final diags = <Diagnostic>[];
    for (final c in _clang.children(d.cursor)) {
      if (_clang.getCursorKind(c) != CursorKind.fieldDecl) continue;
      final n = _clang.str(_clang.getCursorSpelling(c));
      final t = _type(_clang.getCursorType(c));
      if (_clang.isBitField(c) != 0) {
        diags.add(
          Diagnostic(
            DiagnosticCode.abiMismatch,
            'Struct field $n is a C bit-field; its layout cannot be represented with dart:ffi',
            symbolId: id,
          ),
        );
      }
      if (t is BlockTypeRef ||
          t is ArrayTypeRef ||
          (t is DeclaredTypeRef && t.name.startsWith('objc.'))) {
        diags.add(
          Diagnostic(
            DiagnosticCode.unsupportedType,
            'Struct field $n has an unsupported type ${t.display}',
            symbolId: id,
          ),
        );
      }
      fields.add(
        ApiField(
          id: '$id#$n',
          name: n,
          type: t,
          modifiers: const {Modifier.public},
        ),
      );
    }
    final bad = diags.isNotEmpty || fields.isEmpty;
    return ApiType(
      id: id,
      name: d.name,
      kind: TypeKind.struct,
      namespace: d.module,
      provenance: _provenance(d),
      fields: fields,
      modifiers: const {Modifier.public},
      availability: _availability(d.cursor),
      visibility: d.isPrivate ? ApiVisibility.private : ApiVisibility.public,
      support: d.isPrivate || bad
          ? SupportStatus.unsupported
          : SupportStatus.supported,
      diagnostics: [
        ...diags,
        if (fields.isEmpty)
          Diagnostic(
            DiagnosticCode.unsupportedType,
            'Opaque or empty struct',
            symbolId: id,
          ),
        if (d.isPrivate)
          Diagnostic(
            DiagnosticCode.privateApi,
            'Private declaration',
            symbolId: id,
          ),
      ],
    );
  }

  // ------------------------------------------------------------------ types

  static const _typedefPrimitives = {
    'BOOL': PrimitiveKind.boolean,
    'NSInteger': PrimitiveKind.long,
    'NSUInteger': PrimitiveKind.uint64,
    'CGFloat': PrimitiveKind.double_,
    'NSTimeInterval': PrimitiveKind.double_,
    'int8_t': PrimitiveKind.byte,
    'int16_t': PrimitiveKind.short,
    'int32_t': PrimitiveKind.int_,
    'int64_t': PrimitiveKind.long,
    'uint8_t': PrimitiveKind.uint8,
    'uint16_t': PrimitiveKind.uint16,
    'uint32_t': PrimitiveKind.uint32,
    'uint64_t': PrimitiveKind.uint64,
    'unichar': PrimitiveKind.uint16,
  };

  Nullability _nullability(CXType t) => switch (_clang.getNullability(t)) {
    NullabilityC.nonNull => Nullability.nonnull,
    NullabilityC.nullable => Nullability.nullable,
    _ => Nullability.unknown,
  };

  /// Converts a libclang type into a [TypeRef].
  TypeRef _type(CXType t, [int depth = 0]) {
    if (depth > 32) return const DeclaredTypeRef('objc.unsupported');
    switch (t.kind) {
      case TypeKindC.attributed:
        return _type(
          _clang.getModifiedType(t),
          depth + 1,
        ).withNullability(_nullability(t));
      case TypeKindC.elaborated:
        return _type(_clang.getNamedType(t), depth + 1);
      case TypeKindC.unexposed:
        // Macro-qualified types (`API_AVAILABLE(...) NSString *`) are not
        // exposed by libclang: desugar through the canonical type and keep
        // the nullability, which libclang computes through the sugar.
        final canonical = _clang.getCanonicalType(t);
        if (canonical.kind == TypeKindC.unexposed) {
          return const DeclaredTypeRef('objc.unsupported');
        }
        return _type(canonical, depth + 1).withNullability(_nullability(t));
      case TypeKindC.typedef:
        final name = _clang.str(_clang.getTypedefName(t));
        final prim = _typedefPrimitives[name];
        if (prim != null) return PrimitiveTypeRef(prim);
        if (name == 'instancetype') return DeclaredTypeRef(_currentType);
        if (name == 'id') return const DeclaredTypeRef('objc.id');
        if (name == 'SEL') return const DeclaredTypeRef('objc.SEL');
        if (name == 'Class') return const DeclaredTypeRef('objc.Class');
        // Typedef of an enum (NS_ENUM / NS_OPTIONS) keeps the enum identity.
        final enumId = _byName[name];
        if (enumId != null && _decls[enumId]?.kind == CursorKind.enumDecl) {
          return DeclaredTypeRef(enumId);
        }
        return _type(_clang.getCanonicalType(t), depth + 1);
      case TypeKindC.objcObjectPointer:
        return _objectPointer(_clang.getPointeeType(t), depth);
      case TypeKindC.objcId:
        return const DeclaredTypeRef('objc.id');
      case TypeKindC.objcClass:
        return const DeclaredTypeRef('objc.Class');
      case TypeKindC.objcSel:
        return const DeclaredTypeRef('objc.SEL');
      case TypeKindC.blockPointer:
        final fn = _clang.getPointeeType(t);
        final params = [
          for (var i = 0; i < _clang.getNumArgTypes(fn); i++)
            _type(_clang.getArgType(fn, i), depth + 1),
        ];
        return BlockTypeRef(_type(_clang.getResultType(fn), depth + 1), params);
      case TypeKindC.pointer:
        return PointerTypeRef(_type(_clang.getPointeeType(t), depth + 1));
      case TypeKindC.record || TypeKindC.enum_:
        final decl = _clang.getTypeDeclaration(t);
        final name = _clang.str(_clang.getCursorSpelling(decl));
        final id = _byName[_tagAlias[name] ?? name];
        return DeclaredTypeRef(id ?? 'objc.unsupported');
      case TypeKindC.constantArray:
        return ArrayTypeRef(_type(_clang.getArrayElementType(t), depth + 1));
      case TypeKindC.void_:
        return const PrimitiveTypeRef(PrimitiveKind.void_);
      case TypeKindC.bool_:
        return const PrimitiveTypeRef(PrimitiveKind.boolean);
      case TypeKindC.charS || TypeKindC.schar:
        return const PrimitiveTypeRef(PrimitiveKind.byte);
      case TypeKindC.charU || TypeKindC.uchar:
        return const PrimitiveTypeRef(PrimitiveKind.uint8);
      case TypeKindC.char16 || TypeKindC.ushort:
        return const PrimitiveTypeRef(PrimitiveKind.uint16);
      case TypeKindC.short:
        return const PrimitiveTypeRef(PrimitiveKind.short);
      case TypeKindC.int_:
        return const PrimitiveTypeRef(PrimitiveKind.int_);
      case TypeKindC.uint:
        return const PrimitiveTypeRef(PrimitiveKind.uint32);
      case TypeKindC.long || TypeKindC.longLong:
        return const PrimitiveTypeRef(PrimitiveKind.long);
      case TypeKindC.ulong || TypeKindC.ulongLong:
        return const PrimitiveTypeRef(PrimitiveKind.uint64);
      case TypeKindC.float:
        return const PrimitiveTypeRef(PrimitiveKind.float);
      case TypeKindC.double_:
        return const PrimitiveTypeRef(PrimitiveKind.double_);
      default:
        return const DeclaredTypeRef('objc.unsupported');
    }
  }

  TypeRef _objectPointer(CXType pointee, int depth) {
    // `NSArray<NSString *> *`, `id<NSCopying>`, `UIView *`
    final base = _clang.objcBaseType(pointee);
    final baseName = _clang.str(_clang.getTypeSpelling(base));
    final args = [
      for (var i = 0; i < _clang.numObjCTypeArgs(pointee); i++)
        _type(_clang.objcTypeArg(pointee, i), depth + 1),
    ];
    if (baseName == 'id' || baseName.isEmpty) {
      final n = _clang.numObjCProtocolRefs(pointee);
      if (n == 1) {
        final pid =
            _protocolByName[_clang.str(
              _clang.getCursorSpelling(_clang.objcProtocolDecl(pointee, 0)),
            )];
        if (pid != null) return DeclaredTypeRef(pid);
      }
      return const DeclaredTypeRef('objc.id');
    }
    if (baseName == 'Class') return const DeclaredTypeRef('objc.Class');
    final id = _byName[baseName];
    return DeclaredTypeRef(id ?? 'objc.unsupported', typeArguments: args);
  }
}
