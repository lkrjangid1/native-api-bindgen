import 'dart:collection';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';

const _generatorId = 'flutter-android/dart-jni';

/// Lints that generated code intentionally does not follow. Generated code
/// mirrors Java names (e.g. `ACTION_VIEW`) and uses `package:jni` internals
/// the same way `jnigen` output does.
const _ignores = [
  'camel_case_types',
  'comment_references',
  'constant_identifier_names',
  'deprecated_member_use_from_same_package',
  'implementation_imports',
  'invalid_use_of_internal_member',
  'library_prefixes',
  'non_constant_identifier_names',
  'no_leading_underscores_for_local_identifiers',
  'public_member_api_docs',
  'unnecessary_cast',
  'unnecessary_non_null_assertion',
  'unused_element',
  'unused_import',
  'unused_field',
  'lines_longer_than_80_chars',
  'sort_constructors_first',
];

/// Options for [DartJniEmitter].
final class DartJniOptions {
  /// Creates options.
  const DartJniOptions({
    this.minApi = const ApiVersion(24),
    this.mode = GenerationMode.strictNative,
    this.callbacks = true,
    this.runtimeImport = 'package:native_api_runtime/native_api_runtime.dart',
  });

  /// Minimum supported API; newer symbols get runtime guards.
  final ApiVersion minApi;

  /// Type-mapping mode.
  final GenerationMode mode;

  /// Generate interface implementations (callbacks).
  final bool callbacks;

  /// Import URI of the runtime package.
  final String runtimeImport;
}

/// Emits Dart bindings over `package:jni` from IR (TRD §28–§29).
///
/// Output shape: one library per Java package (`android/content.dart`) and
/// an umbrella `bindings.dart`. Every Java type becomes a zero-cost Dart
/// extension type over `JObject`; JNI IDs are lazily initialised statics, so
/// unused classes and members are tree-shaken. There is no registry.
final class DartJniEmitter {
  /// Creates an emitter. [module] is planned internally.
  DartJniEmitter(ApiModule module, {this.options = const DartJniOptions()})
    : module = planJvmTarget(module, callbacks: options.callbacks) {
    for (final t in this.module.types) {
      if (t.isGeneratable) _types[t.id] = t;
    }
  }

  /// Planned module.
  final ApiModule module;

  /// Options.
  final DartJniOptions options;

  final _types = SplayTreeMap<String, ApiType>();
  final _bindings = <BindingMapEntry>[];
  final _diagnostics = <Diagnostic>[];
  final _namesCache = <String, _TypeNames>{};

  /// Output-relative library path for a namespace.
  static String libraryPath(String namespace) =>
      '${namespace.isEmpty ? r'$default' : namespace.replaceAll('.', '/')}.dart';

  /// Generates all files.
  GenerationOutput emit() {
    final byNs = SplayTreeMap<String, List<ApiType>>();
    for (final t in _types.values) {
      (byNs[t.namespace] ??= []).add(t);
    }
    final files = <GeneratedFile>[];
    for (final e in byNs.entries) {
      files.add(GeneratedFile(libraryPath(e.key), _library(e.key, e.value)));
    }
    final umbrella = StringBuffer(generatedHeader(module))
      ..writeln()
      ..writeln(
        '/// Umbrella library for the generated bindings. Individual libraries',
      )
      ..writeln(
        '/// can be imported directly; unused declarations are tree-shaken.',
      )
      ..writeln('library;')
      ..writeln();
    // Two Java packages may declare the same simple name; the first package
    // (sorted) is exported, later duplicates are hidden from the umbrella and
    // must be imported from their own library.
    final exported = <String>{};
    for (final e in byNs.entries) {
      final hidden = <String>[];
      for (final t in e.value) {
        for (final n in [
          dartName(t),
          if (options.callbacks &&
              t.isInterface &&
              _callbackMethods(t).isNotEmpty)
            '\$${dartName(t)}',
        ]) {
          if (!exported.add(n)) hidden.add(n);
        }
      }
      if (hidden.isNotEmpty) {
        _diagnostics.add(
          Diagnostic(
            DiagnosticCode.generationFailure,
            'Hidden from bindings.dart (name clash): ${hidden.join(', ')}; import ${libraryPath(e.key)} directly',
            severity: Severity.info,
          ),
        );
      }
      umbrella.writeln(
        "export '${libraryPath(e.key)}'${hidden.isEmpty ? '' : ' hide ${hidden.join(', ')}'};",
      );
    }
    files.add(GeneratedFile('bindings.dart', umbrella.toString()));
    return GenerationOutput(
      files: files,
      bindings: _bindings,
      module: module,
      diagnostics: _diagnostics,
    );
  }

  // ---------------------------------------------------------------- library

  String _library(String ns, List<ApiType> types) {
    final path = libraryPath(ns);
    final resolver = _Resolver(this, ns);
    final mapper = DartJniTypeMapper(resolver, mode: options.mode);
    final body = StringBuffer();
    for (final t in types) {
      _emitType(body, t, mapper, path);
    }
    final b = StringBuffer(generatedHeader(module))
      ..writeln()
      ..writeln('// ignore_for_file: ${_ignores.join(', ')}')
      ..writeln()
      ..writeln('/// Bindings for Java package `$ns`.')
      ..writeln('library;')
      ..writeln()
      ..writeln("import 'package:jni/_internal.dart' as jnii\$;")
      ..writeln("import 'package:jni/jni.dart' as jni\$;")
      ..writeln("import '${options.runtimeImport}' as rt\$;");
    for (final other in resolver.usedNamespaces.toList()..sort()) {
      b.writeln(
        "import '${relativeImport(path, libraryPath(other))}' as ${Identifiers.packagePrefix(other)};",
      );
    }
    b
      ..writeln()
      ..write(body.toString().trimRight())
      ..writeln();
    return b.toString();
  }

  // ------------------------------------------------------------------ names

  /// Dart type name generated for [t].
  String dartName(ApiType t) => DartJniTypeMapper.dartTypeName(t);

  /// Ancestors (generated only), nearest first: superclass chain then
  /// interfaces, breadth-first, deduplicated.
  List<ApiType> _ancestors(ApiType t) {
    final out = <ApiType>[];
    final seen = <String>{t.id};
    final queue = Queue<ApiType>.of([t]);
    while (queue.isNotEmpty) {
      final x = queue.removeFirst();
      for (final s in [?x.superClass, ...x.interfaces]) {
        final st = _types[(s as DeclaredTypeRef).name];
        if (st != null && seen.add(st.id)) {
          out.add(st);
          queue.add(st);
        }
      }
    }
    return out;
  }

  List<ApiType> _directSupers(ApiType t) => [
    for (final s in [?t.superClass, ...t.interfaces])
      ?_types[(s as DeclaredTypeRef).name],
  ];

  _TypeNames _names(ApiType t) {
    final cached = _namesCache[t.id];
    if (cached != null) return cached;

    String key(ApiMethod m) =>
        '${m.name}(${m.id.substring(m.id.indexOf('(') + 1)}';
    final declared = t.methods.where((m) => m.isGeneratable).toList();
    final visible = <String, ApiMethod>{for (final m in declared) key(m): m};
    for (final a in _ancestors(t)) {
      for (final m in a.methods) {
        if (m.isGeneratable && !m.isStatic && !m.isConstructor) {
          visible.putIfAbsent(key(m), () => m);
        }
      }
    }
    final assigned = OverloadNamer.assign(visible.values);
    final methodNames = <String, String>{
      for (final m in declared) m.id: assigned[m.id]!,
    };

    // Instance member names visible through supertypes: name -> provider id.
    final inherited = <String, Set<String>>{};
    for (final s in _directSupers(t)) {
      _names(s).instanceMembers.forEach((name, providers) {
        (inherited[name] ??= {}).addAll(providers);
      });
    }

    final instanceMembers = <String, Set<String>>{
      for (final e in inherited.entries) e.key: {...e.value},
    };
    for (final m in declared.where((m) => !m.isStatic && !m.isConstructor)) {
      instanceMembers[methodNames[m.id]!] = {m.id};
    }

    final fieldNames = <String, String>{};
    final methodSet = methodNames.values.toSet();
    for (final f in t.fields.where((f) => f.isGeneratable)) {
      var n = Identifiers.dartMember(f.name);
      if (methodSet.contains(n)) n = '$n\$field';
      fieldNames[f.id] = n;
      if (!f.isStatic) instanceMembers[n] = {f.id};
    }
    // Static names must not collide with any visible instance member name.
    for (final m in declared.where((m) => m.isStatic)) {
      if (instanceMembers.containsKey(methodNames[m.id])) {
        methodNames[m.id] = '${methodNames[m.id]}\$static';
      }
    }
    for (final f in t.fields.where((f) => f.isGeneratable && f.isStatic)) {
      if (instanceMembers.containsKey(fieldNames[f.id]) ||
          fieldNames[f.id] == 'type') {
        fieldNames[f.id] = '${fieldNames[f.id]}\$static';
      }
    }
    // Members inherited from two different supertypes with different
    // declarations conflict in Dart; they are redeclared in this type.
    final conflicts = <String, String>{};
    for (final e in inherited.entries) {
      final declaredHere =
          declared.any((m) => methodNames[m.id] == e.key) ||
          fieldNames.containsValue(e.key);
      if (e.value.length > 1 && !declaredHere) {
        conflicts[e.key] = (e.value.toList()..sort()).first;
      }
    }
    return _namesCache[t.id] = _TypeNames(
      methodNames,
      fieldNames,
      instanceMembers,
      conflicts,
    );
  }

  // ------------------------------------------------------------------ types

  void _emitType(
    StringBuffer b,
    ApiType t,
    DartJniTypeMapper mapper,
    String file,
  ) {
    final name = dartName(t);
    final names = _names(t);
    final supers = <String>[
      for (final s in _directSupers(t))
        mapper.map(DeclaredTypeRef(s.id)).dartType,
    ];
    if (supers.isEmpty) supers.add('jni\$.JObject');
    final internal = t.id.replaceAll('.', '/');

    _typeDoc(b, t);
    if (t.isDeprecated) {
      b.writeln("@Deprecated('${_deprecationText(t.availability)}')");
    }
    // The representation name is unique per type: extension types that
    // implement several generated supertypes must not inherit two distinct
    // members with the same name.
    b.writeln(
      'extension type $name._(jni\$.JObject _\$$name) implements ${supers.join(', ')} {',
    );
    b.writeln("  static final _\$class = jni\$.JClass.forName(r'$internal');");
    b.writeln();
    b.writeln('  /// `package:jni` type descriptor for `${t.id}`.');
    b.writeln('  static const jni\$.JType<$name> type = _\$$name\$Type();');
    _binding(t.id, name, file, 'package:jni JClass');

    final ctx = _MemberContext(t, name, mapper, file);
    for (final f
        in t.fields.where((f) => f.isGeneratable).toList()
          ..sort((a, b) => a.name.compareTo(b.name))) {
      _emitField(b, ctx, f, names.fieldNames[f.id]!);
    }
    final ctors = t.methods
        .where((m) => m.isGeneratable && m.isConstructor)
        .toList();
    final ctorNames = OverloadNamer.assign(ctors);
    for (final m in ctors..sort((a, b) => a.id.compareTo(b.id))) {
      _emitConstructor(b, ctx, m, ctorNames[m.id]!);
    }
    final methods =
        t.methods.where((m) => m.isGeneratable && !m.isConstructor).toList()
          ..sort(
            (a, b) =>
                names.methodNames[a.id]!.compareTo(names.methodNames[b.id]!),
          );
    for (final m in methods) {
      _emitMethod(b, ctx, m, names.methodNames[m.id]!);
    }
    for (final e
        in names.conflicts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final node = module.nodeById(e.value);
      if (node is ApiMethod) {
        _emitMethod(b, ctx, node, e.key, redeclared: true);
      } else if (node is ApiField) {
        _emitField(b, ctx, node, e.key, redeclared: true);
      }
    }
    // Marker interfaces (no instance methods) have nothing to implement.
    final implementable =
        options.callbacks && t.isInterface && _callbackMethods(t).isNotEmpty;
    if (implementable) _emitImplementation(b, ctx);
    b.writeln('}');
    b.writeln();
    b.writeln('final class _\$$name\$Type extends jni\$.JType<$name> {');
    b.writeln('  const _\$$name\$Type();');
    b.writeln();
    b.writeln('  @override');
    b.writeln("  String get signature => r'L$internal;';");
    b.writeln('}');
    b.writeln();
    if (implementable) _emitInterfaceMixin(b, ctx);
  }

  void _typeDoc(StringBuffer b, ApiType t) {
    b.writeln('/// Native API: `${t.id}` (${_kindName(t.kind)})');
    b.writeln('///');
    _availabilityDoc(b, t.availability, t);
    if (t.threading != Threading.unspecified) {
      b.writeln('/// - Threading: ${_threadingText(t.threading)}');
    }
    if (t.typeParameters.isNotEmpty) {
      b.writeln(
        '/// - Type parameters: `<${t.typeParameters.map((p) => p.bounds.isEmpty ? p.name : '${p.name} extends ${p.bounds.map((x) => x.display).join(' & ')}').join(', ')}>` (erased)',
      );
    }
    if (t.superClass != null) {
      b.writeln('/// - Superclass: `${t.superClass!.display}`');
    }
    if (t.interfaces.isNotEmpty) {
      b.writeln(
        '/// - Interfaces: ${t.interfaces.map((i) => '`${i.display}`').join(', ')}',
      );
    }
    _diagnosticsDoc(b, t.diagnostics);
    if (t.documentation.reference != null) {
      b.writeln('/// - Reference: <${t.documentation.reference}>');
    }
    if (t.isInterface && options.callbacks) {
      b.writeln('///');
      b.writeln('/// Implement in Dart with [${dartName(t)}.implement].');
    }
  }

  void _availabilityDoc(StringBuffer b, Availability a, ApiNode n) {
    if (a.introduced != null) {
      final guarded = a.introduced! > options.minApi;
      b.writeln(
        '/// - Android API: ${a.introduced}+${guarded ? ' (guarded at runtime: minApi is ${options.minApi})' : ''}',
      );
    }
    if (a.deprecated != null) {
      b.writeln('/// - Deprecated in Android API ${a.deprecated}');
    }
    if (a.removed != null) {
      b.writeln('/// - Removed in Android API ${a.removed}');
    }
  }

  void _diagnosticsDoc(StringBuffer b, List<Diagnostic> diags) {
    for (final d in diags) {
      b.writeln(
        '/// - Note ${d.code.code} ${d.code.label}: ${_docSafe(d.message)}',
      );
    }
  }

  void _memberDoc(
    StringBuffer b,
    ApiNode n, {
    String indent = '  ',
    String? generatedAs,
  }) {
    final lines = StringBuffer();
    lines.writeln('/// Native API: `${n.id}`');
    lines.writeln('///');
    _availabilityDoc(lines, n.availability, n);
    if (n is ApiMethod) {
      if (n.threading != Threading.unspecified) {
        lines.writeln('/// - Threading: ${_threadingText(n.threading)}');
      }
      if (n.permissions.isNotEmpty) {
        lines.writeln(
          '/// - Permissions: ${n.permissions.map((p) => '`$p`').join(', ')}',
        );
      }
      if (n.throws.isNotEmpty) {
        lines.writeln(
          '/// - Throws (Java): ${n.throws.map((x) => '`${x.display}`').join(', ')}; surfaced as `NativeJavaException`',
        );
      }
      if (n.modifiers.contains(Modifier.varargs)) {
        lines.writeln('/// - Varargs: pass the last argument as an array');
      }
      for (final p in n.parameters) {
        if (p.type is! PrimitiveTypeRef) {
          lines.writeln(
            '/// - `${Identifiers.dartMember(p.name)}`: `${p.type.display}`, ${_nullText(p.type.nullability)}',
          );
        }
      }
      if (!n.isConstructor && n.returnType is! PrimitiveTypeRef) {
        lines.writeln(
          '/// - Returns `${n.returnType.display}`, ${_nullText(n.returnType.nullability)}',
        );
      }
    }
    if (n is ApiField && n.constantValue != null) {
      lines.writeln(
        '/// - Constant value (inlined from the SDK): `${_docSafe(n.constantValue!.literal)}`',
      );
    }
    for (final a in n.annotations.where(
      (a) => a.classification == AnnotationClassification.preservable,
    )) {
      lines.writeln(
        '/// - Annotation: `@${a.simpleName}`${a.values.isEmpty ? '' : ' ${_docSafe(a.values.entries.map((e) => '${e.key}=${e.value}').join(', '))}'}',
      );
    }
    if (generatedAs != null) {
      lines.writeln(
        '/// - Overload mapped to `$generatedAs` (see binding_map.json)',
      );
    }
    _diagnosticsDoc(lines, n.diagnostics);
    if (n.documentation.reference != null) {
      lines.writeln('/// - Reference: <${n.documentation.reference}>');
    }
    for (final l in lines.toString().trimRight().split('\n')) {
      b.writeln('$indent$l');
    }
    if (n.isDeprecated) {
      b.writeln("$indent@Deprecated('${_deprecationText(n.availability)}')");
    }
  }

  String _guard(ApiNode n, String indent) {
    final intro = n.availability.introduced;
    if (intro == null || !(intro > options.minApi)) return '';
    return "${indent}rt\$.AndroidApi.require(${intro.major}, ${intro.minor}, r'${n.id}');\n";
  }

  // ----------------------------------------------------------------- fields

  void _emitField(
    StringBuffer b,
    _MemberContext c,
    ApiField f,
    String dart, {
    bool redeclared = false,
  }) {
    final m = c.mapper.map(f.type);
    b.writeln();
    final cv = f.constantValue;
    if (cv != null && f.isStatic && f.isFinal) {
      final (type, literal) = _constLiteral(cv, m);
      if (literal != null) {
        _memberDoc(b, f);
        b.writeln('  static const $type $dart = $literal;');
        _binding(f.id, '${c.name}.$dart', c.file, 'compile-time constant');
        return;
      }
    }
    final idName = '_\$f\$$dart';
    final nullable =
        !m.isPrimitive && f.type.nullability != Nullability.nonnull;
    final dartType = _apiType(f.type, m);
    final getter = nullable ? 'getNullable' : 'get';
    final jType = m.ergonomicString ? 'jni\$.JString.type' : m.jniType;
    String read(String target) {
      final raw = '$idName.$getter($target, $jType)';
      return m.ergonomicString
          ? '$raw${nullable ? '?' : ''}.toDartString(releaseOriginal: true)'
          : raw;
    }

    if (f.isStatic) {
      b.writeln(
        "  static final $idName = _\$class.staticFieldId(r'${f.name}', r'${f.nativeDescriptor}');",
      );
      _memberDoc(b, f);
      final guard = _guard(f, '    ');
      b.writeln('  static $dartType get $dart {');
      b.write(guard);
      b.writeln('    return ${read('_\$class')};');
      b.writeln('  }');
      if (!f.isFinal) {
        b.writeln(
          '  static set $dart($dartType value) ${_setterBody(_fieldSet(idName, '_\$class', jType, m, nullable))}',
        );
      }
    } else {
      b.writeln(
        "  static final $idName = _\$class.instanceFieldId(r'${f.name}', r'${f.nativeDescriptor}');",
      );
      _memberDoc(b, f);
      b.writeln('  $dartType get $dart => ${read('this')};');
      if (!f.isFinal) {
        b.writeln(
          '  set $dart($dartType value) ${_setterBody(_fieldSet(idName, 'this', jType, m, nullable))}',
        );
      }
    }
    _binding(
      f.id,
      '${c.name}.$dart',
      c.file,
      redeclared ? 'package:jni field ID (redeclared)' : 'package:jni field ID',
    );
  }

  String _fieldSet(
    String id,
    String target,
    String jType,
    DartJniType m,
    bool nullable,
  ) {
    if (!m.ergonomicString) return '$id.set($target, $jType, value)';
    final q = nullable ? '?' : '';
    return '{ final j = value$q.toJString(); try { $id.set($target, $jType, j); } finally { j$q.release(); } }';
  }

  static String _setterBody(String stmt) =>
      stmt.startsWith('{') ? stmt : '=> $stmt;';

  (String, String?) _constLiteral(ConstantValue cv, DartJniType m) {
    switch (cv.type) {
      case 'string':
        return ('String', dartStringLiteral(cv.literal));
      case 'boolean':
        return ('bool', cv.literal);
      case 'float' || 'double':
        final lit = switch (cv.literal) {
          'NaN' => 'double.nan',
          'Infinity' => 'double.infinity',
          '-Infinity' => '-double.infinity',
          final s =>
            s.contains('.') || s.contains('e') || s.contains('E') ? s : '$s.0',
        };
        return ('double', lit);
      case 'int' || 'long' || 'short' || 'byte' || 'char':
        return ('int', cv.literal);
      default:
        return ('', null);
    }
  }

  // ---------------------------------------------------------------- methods

  String _apiType(TypeRef t, DartJniType m) => m.isPrimitive
      ? m.dartType
      : (t.nullability == Nullability.nonnull ? m.dartType : '${m.dartType}?');

  /// Parameter list and argument conversion for a call.
  ({String params, String pre, String post, String args}) _params(
    ApiMethod m,
    DartJniTypeMapper mapper,
    Map<String, TypeRef> tv,
  ) {
    final params = <String>[];
    final args = <String>[];
    final pre = StringBuffer();
    final post = StringBuffer();
    final used = <String>{};
    for (final p in m.parameters) {
      var n = Identifiers.dartMember(p.name);
      while (!used.add(n)) {
        n = '$n\$';
      }
      final mt = mapper.map(p.type, typeVariableBounds: tv);
      params.add('${_apiType(p.type, mt)} $n');
      if (mt.ergonomicString) {
        final nullable = p.type.nullability != Nullability.nonnull;
        pre.writeln('    final _\$$n = $n${nullable ? '?' : ''}.toJString();');
        post.writeln('      _\$$n${nullable ? '?' : ''}.release();');
        args.add('_\$$n');
      } else if (mt.argWrapper != null) {
        args.add('${mt.argWrapper}($n)');
      } else {
        args.add(n);
      }
    }
    return (
      params: params.join(', '),
      pre: pre.toString(),
      post: post.toString(),
      args: args.join(', '),
    );
  }

  Map<String, TypeRef> _typeVars(ApiType owner, ApiMethod m) => {
    for (final p in owner.typeParameters)
      p.name: p.bounds.isEmpty
          ? const DeclaredTypeRef('java.lang.Object')
          : p.bounds.first,
    for (final p in m.typeParameters)
      p.name: p.bounds.isEmpty
          ? const DeclaredTypeRef('java.lang.Object')
          : p.bounds.first,
  };

  void _emitConstructor(
    StringBuffer b,
    _MemberContext c,
    ApiMethod m,
    String ctorName,
  ) {
    final tv = _typeVars(c.type, m);
    final ps = _params(m, c.mapper, tv);
    final idName = '_\$c\$$ctorName';
    final dartCtor = ctorName.isEmpty ? c.name : '${c.name}.$ctorName';
    b.writeln();
    b.writeln(
      "  static final $idName = _\$class.constructorId(r'${m.nativeDescriptor}');",
    );
    _memberDoc(b, m, generatedAs: ctorName.isEmpty ? null : dartCtor);
    b.writeln('  factory $dartCtor(${ps.params}) {');
    b.write(_guard(m, '    '));
    b.write(ps.pre);
    final call =
        'rt\$.guardJni(() => $idName.call<${c.name}>(_\$class, [${ps.args}]))';
    if (ps.post.isEmpty) {
      b.writeln('    return $call;');
    } else {
      b.writeln('    try {');
      b.writeln('      return $call;');
      b.writeln('    } finally {');
      b.write(ps.post);
      b.writeln('    }');
    }
    b.writeln('  }');
    _binding(m.id, dartCtor, c.file, 'package:jni JConstructorId');
  }

  void _emitMethod(
    StringBuffer b,
    _MemberContext c,
    ApiMethod m,
    String dart, {
    bool redeclared = false,
  }) {
    final tv = _typeVars(_types[SymbolIds.ownerOf(m.id)] ?? c.type, m);
    final ps = _params(m, c.mapper, tv);
    final ret = c.mapper.map(m.returnType, typeVariableBounds: tv);
    final isVoid =
        m.returnType is PrimitiveTypeRef &&
        (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;
    final nullable =
        !ret.isPrimitive && m.returnType.nullability != Nullability.nonnull;
    final dartRet = isVoid ? 'void' : _apiType(m.returnType, ret);
    final idName = '_\$m\$$dart';
    final kind = m.isStatic ? 'staticMethodId' : 'instanceMethodId';
    final target = m.isStatic ? '_\$class' : 'this';
    final jType = ret.ergonomicString ? 'jni\$.JString.type' : ret.jniType;
    var call =
        '$idName.${nullable ? 'callNullable' : 'call'}($target, $jType, [${ps.args}])';
    if (ret.ergonomicString) {
      call = '$call${nullable ? '?' : ''}.toDartString(releaseOriginal: true)';
    }
    b.writeln();
    b.writeln(
      "  static final $idName = _\$class.$kind(r'${m.name}', r'${m.nativeDescriptor}');",
    );
    final plain = Identifiers.dartMember(m.name);
    _memberDoc(b, m, generatedAs: dart == plain ? null : '${c.name}.$dart');
    if (redeclared) {
      b.writeln('  // Redeclared: inherited from more than one supertype.');
    }
    b.writeln('  ${m.isStatic ? 'static ' : ''}$dartRet $dart(${ps.params}) {');
    b.write(_guard(m, '    '));
    b.write(ps.pre);
    final stmt = isVoid
        ? 'rt\$.guardJni(() => $call);'
        : 'return rt\$.guardJni(() => $call);';
    if (ps.post.isEmpty) {
      b.writeln('    $stmt');
    } else {
      b.writeln('    try {');
      b.writeln('      $stmt');
      b.writeln('    } finally {');
      b.write(ps.post);
      b.writeln('    }');
    }
    b.writeln('  }');
    _binding(
      m.id,
      '${c.name}.$dart',
      c.file,
      redeclared
          ? 'package:jni method ID (redeclared)'
          : 'package:jni method ID',
    );
  }

  // -------------------------------------------------------------- callbacks

  List<(ApiMethod, String)> _callbackMethods(ApiType t) {
    final names = _names(t);
    return [
      for (final m in t.methods)
        if (m.isGeneratable && !m.isStatic && !m.isConstructor)
          (m, names.methodNames[m.id]!),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
  }

  bool _isVoid(ApiMethod m) =>
      m.returnType is PrimitiveTypeRef &&
      (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;

  void _emitImplementation(StringBuffer b, _MemberContext c) {
    final t = c.type;
    final mixin = '\$${c.name}';
    final methods = _callbackMethods(t);
    b.writeln();
    b.writeln('  static final Map<int, $mixin> _\$impls = {};');
    b.writeln();
    // Direct (same-thread) entry point used by package:jni when Java calls
    // on the isolate's thread; wakes the event loop for pending microtasks.
    b.writeln(
      '  static jnii\$.JObjectPtr _\$invoke(int port, jnii\$.JObjectPtr descriptor, jnii\$.JObjectPtr args) {',
    );
    b.writeln(
      '    final \$r = _\$invokeMethod(port, jnii\$.MethodInvocation.fromAddresses(0, descriptor.address, args.address));',
    );
    b.writeln('    rt\$.NativeCallbacks.wakeEventLoop();');
    b.writeln('    return \$r;');
    b.writeln('  }');
    b.writeln();
    b.writeln(
      '  static final jnii\$.Pointer<jnii\$.NativeFunction<jnii\$.JObjectPtr Function(jnii\$.Int64, jnii\$.JObjectPtr, jnii\$.JObjectPtr)>> _\$invokePointer =',
    );
    b.writeln('      jnii\$.Pointer.fromFunction(_\$invoke);');
    b.writeln();
    b.writeln(
      '  static jnii\$.Pointer<jnii\$.Void> _\$invokeMethod(int \$p, jnii\$.MethodInvocation \$i) {',
    );
    b.writeln(
      '    final \$d = \$i.methodDescriptor.toDartString(releaseOriginal: true);',
    );
    if (methods.any((e) => e.$1.parameters.isNotEmpty)) {
      b.writeln('    final \$a = \$i.args;');
    }
    for (final (m, dart) in methods) {
      final tv = _typeVars(t, m);
      final args = <String>[];
      for (var i = 0; i < m.parameters.length; i++) {
        args.add(
          _unbox(
            m.parameters[i].type,
            c.mapper.map(m.parameters[i].type, typeVariableBounds: tv),
            '\$a![$i]',
          ),
        );
      }
      final call = '_\$impls[\$p]!.$dart(${args.join(', ')})';
      b.writeln("    if (\$d == r'${m.name}${m.nativeDescriptor}') {");
      b.writeln('      try {');
      if (_isVoid(m)) {
        b.writeln('        $call;');
        b.writeln('        return jnii\$.nullptr;');
      } else {
        b.writeln('        final \$r = $call;');
        b.writeln(
          '        return ${_box(m.returnType, c.mapper.map(m.returnType, typeVariableBounds: tv), '\$r')};',
        );
      }
      b.writeln('      } catch (e, st) {');
      if (_isVoid(m)) {
        b.writeln(
          "        if (rt\$.NativeCallbacks.handleVoidCallbackError(e, st, r'${m.id}')) return jnii\$.nullptr;",
        );
      } else {
        b.writeln(
          "        rt\$.NativeCallbacks.reportPropagated(e, st, r'${m.id}');",
        );
      }
      b.writeln(
        '        return jnii\$.ProtectedJniExtensions.newDartException(e);',
      );
      b.writeln('      }');
      b.writeln('    }');
    }
    b.writeln('    return jnii\$.nullptr;');
    b.writeln('  }');
    b.writeln();
    b.writeln(
      '  /// Adds a Dart implementation of `${t.id}` to [implementer], for',
    );
    b.writeln('  /// objects implementing several interfaces.');
    b.writeln(
      '  static void implementIn(jni\$.JImplementer implementer, $mixin \$impl) {',
    );
    b.writeln('    late final jnii\$.RawReceivePort \$p;');
    b.writeln('    \$p = jnii\$.RawReceivePort((Object? \$m) {');
    b.writeln('      if (\$m == null) {');
    b.writeln('        _\$impls.remove(\$p.sendPort.nativePort);');
    b.writeln('        \$p.close();');
    b.writeln('        return;');
    b.writeln('      }');
    b.writeln(
      '      final \$i = jnii\$.MethodInvocation.fromMessage(\$m as List<dynamic>);',
    );
    b.writeln(
      '      final \$r = _\$invokeMethod(\$p.sendPort.nativePort, \$i);',
    );
    b.writeln('      \$i.args?.release();');
    b.writeln(
      '      jnii\$.ProtectedJniExtensions.returnResult(\$i.result, \$r);',
    );
    b.writeln('    });');
    b.writeln("    implementer.add(r'${t.id}', \$p, _\$invokePointer, [");
    for (final (m, dart) in methods.where((e) => _isVoid(e.$1))) {
      b.writeln(
        "      if (\$impl.$dart\$async) r'${m.name}${m.nativeDescriptor}',",
      );
    }
    b.writeln('    ]);');
    b.writeln('    _\$impls[\$p.sendPort.nativePort] = \$impl;');
    b.writeln('  }');
    b.writeln();
    b.writeln(
      '  /// Creates a Java object implementing `${t.id}` backed by [\$impl].',
    );
    b.writeln('  ///');
    b.writeln(
      '  /// The Dart implementation is retained until the Java proxy is',
    );
    b.writeln(
      '  /// garbage-collected. A `void` callback that throws is reported through',
    );
    b.writeln(
      '  /// `NativeCallbacks` instead of crashing the calling Java thread.',
    );
    b.writeln('  factory ${c.name}.implement($mixin \$impl) {');
    b.writeln('    final \$i = jni\$.JImplementer();');
    b.writeln('    implementIn(\$i, \$impl);');
    b.writeln('    return \$i.implement<${c.name}>();');
    b.writeln('  }');
    _binding(
      '${t.id}#<implement>',
      '${c.name}.implement',
      c.file,
      'package:jni JImplementer',
    );
  }

  void _emitInterfaceMixin(StringBuffer b, _MemberContext c) {
    final t = c.type;
    final mixin = '\$${c.name}';
    final methods = _callbackMethods(t);
    String sig((ApiMethod, String) e) {
      final (m, _) = e;
      final tv = _typeVars(t, m);
      final ret = _isVoid(m)
          ? 'void'
          : _apiType(
              m.returnType,
              c.mapper.map(m.returnType, typeVariableBounds: tv),
            );
      final params = [
        for (final p in m.parameters)
          '${_callbackParamType(p.type, c.mapper.map(p.type, typeVariableBounds: tv))} ${Identifiers.dartMember(p.name)}',
      ];
      return '$ret Function(${params.join(', ')})';
    }

    b.writeln(
      '/// Dart implementation of `${t.id}`; see [${c.name}.implement].',
    );
    b.writeln('abstract base mixin class $mixin {');
    b.writeln('  factory $mixin({');
    for (final e in methods) {
      b.writeln('    required ${sig(e)} ${e.$2},');
      if (_isVoid(e.$1)) b.writeln('    bool ${e.$2}\$async,');
    }
    b.writeln('  }) = _\$${c.name};');
    b.writeln();
    for (final e in methods) {
      final (m, dart) = e;
      final tv = _typeVars(t, m);
      final ret = _isVoid(m)
          ? 'void'
          : _apiType(
              m.returnType,
              c.mapper.map(m.returnType, typeVariableBounds: tv),
            );
      final params = [
        for (final p in m.parameters)
          '${_callbackParamType(p.type, c.mapper.map(p.type, typeVariableBounds: tv))} ${Identifiers.dartMember(p.name)}',
      ];
      b.writeln('  /// Implements `${m.id}`.');
      b.writeln('  $ret $dart(${params.join(', ')});');
      if (_isVoid(m)) {
        b.writeln();
        b.writeln(
          '  /// Whether Java calls to [$dart] return without waiting for Dart.',
        );
        b.writeln('  bool get $dart\$async => false;');
      }
      b.writeln();
    }
    b.writeln('}');
    b.writeln();
    b.writeln('final class _\$${c.name} with $mixin {');
    b.writeln('  _\$${c.name}({');
    for (final e in methods) {
      b.writeln('    required ${sig(e)} ${e.$2},');
      if (_isVoid(e.$1)) b.writeln('    this.${e.$2}\$async = false,');
    }
    b.write('  })');
    if (methods.isEmpty) {
      b.writeln(';');
    } else {
      b.writeln(' : ${methods.map((e) => '_${e.$2} = ${e.$2}').join(', ')};');
    }
    b.writeln();
    for (final e in methods) {
      final (m, dart) = e;
      b.writeln('  final ${sig(e)} _$dart;');
      if (_isVoid(m)) {
        b.writeln('  @override');
        b.writeln('  final bool $dart\$async;');
      }
      final tv = _typeVars(t, m);
      final ret = _isVoid(m)
          ? 'void'
          : _apiType(
              m.returnType,
              c.mapper.map(m.returnType, typeVariableBounds: tv),
            );
      final params = [
        for (final p in m.parameters)
          '${_callbackParamType(p.type, c.mapper.map(p.type, typeVariableBounds: tv))} ${Identifiers.dartMember(p.name)}',
      ];
      b.writeln('  @override');
      b.writeln(
        '  $ret $dart(${params.join(', ')}) => _$dart(${m.parameters.map((p) => Identifiers.dartMember(p.name)).join(', ')});',
      );
      b.writeln();
    }
    b.writeln('}');
    b.writeln();
  }

  String _callbackParamType(TypeRef t, DartJniType m) => _apiType(t, m);

  String _unbox(TypeRef t, DartJniType m, String expr) {
    if (t is PrimitiveTypeRef) {
      final (box, conv) = switch (t.kind) {
        PrimitiveKind.boolean => ('JBoolean', 'toDartBool'),
        PrimitiveKind.byte => ('JByte', 'toDartInt'),
        PrimitiveKind.char => ('JCharacter', 'toDartInt'),
        PrimitiveKind.short => ('JShort', 'toDartInt'),
        PrimitiveKind.int_ => ('JInteger', 'toDartInt'),
        PrimitiveKind.long => ('JLong', 'toDartInt'),
        PrimitiveKind.float => ('JFloat', 'toDartDouble'),
        PrimitiveKind.double_ => ('JDouble', 'toDartDouble'),
        PrimitiveKind.void_ => throw StateError('void parameter'),
        PrimitiveKind.uint8 ||
        PrimitiveKind.uint16 ||
        PrimitiveKind.uint32 ||
        PrimitiveKind.uint64 => throw StateError('not a JVM type'),
      };
      return '($expr as jni\$.$box).$conv(releaseOriginal: true)';
    }
    final nonnull = t.nullability == Nullability.nonnull;
    if (m.ergonomicString) {
      return '($expr as jni\$.JString${nonnull ? '' : '?'})${nonnull ? '' : '?'}.toDartString(releaseOriginal: true)';
    }
    return '($expr as ${m.dartType}${nonnull ? '' : '?'})';
  }

  String _box(TypeRef t, DartJniType m, String expr) {
    if (t is PrimitiveTypeRef) {
      final conv = switch (t.kind) {
        PrimitiveKind.boolean => 'toJBoolean',
        PrimitiveKind.byte => 'toJByte',
        PrimitiveKind.char => 'toJCharacter',
        PrimitiveKind.short => 'toJShort',
        PrimitiveKind.int_ => 'toJInteger',
        PrimitiveKind.long => 'toJLong',
        PrimitiveKind.float => 'toJFloat',
        PrimitiveKind.double_ => 'toJDouble',
        PrimitiveKind.void_ => throw StateError('void'),
        PrimitiveKind.uint8 ||
        PrimitiveKind.uint16 ||
        PrimitiveKind.uint32 ||
        PrimitiveKind.uint64 => throw StateError('not a JVM type'),
      };
      return '$expr.$conv().reference.toPointer()';
    }
    if (m.ergonomicString) {
      return '($expr as String?)?.toJString().reference.toPointer() ?? jnii\$.nullptr';
    }
    return '($expr as jni\$.JObject?)?.as(jni\$.JObject.type).reference.toPointer() ?? jnii\$.nullptr';
  }

  // ------------------------------------------------------------------ misc

  void _binding(String id, String generated, String file, String adapter) {
    _bindings.add(
      BindingMapEntry(
        symbolId: id,
        generated: generated,
        file: file,
        generator: _generatorId,
        runtimeAdapter: adapter,
      ),
    );
  }

  static String _kindName(TypeKind k) => switch (k) {
    TypeKind.classType => 'class',
    TypeKind.interfaceType => 'interface',
    TypeKind.enumType => 'enum',
    TypeKind.annotationType => 'annotation',
    TypeKind.recordType => 'record',
    TypeKind.struct => 'struct',
    TypeKind.protocol => 'protocol',
  };

  static String _threadingText(Threading t) => switch (t) {
    Threading.mainThread => 'call on the main thread (`@MainThread`)',
    Threading.uiThread => 'call on the UI thread (`@UiThread`)',
    Threading.workerThread => 'call off the main thread (`@WorkerThread`)',
    Threading.anyThread =>
      'documented as callable from any thread (`@AnyThread`)',
    Threading.actorIsolated => 'actor-isolated',
    Threading.dispatchQueue => 'bound to a dispatch queue',
    Threading.unspecified => 'unspecified',
  };

  static String _nullText(Nullability n) => switch (n) {
    Nullability.nonnull => 'non-null',
    Nullability.nullable => 'nullable',
    Nullability.unknown => 'nullability unknown (treated as nullable)',
  };

  static String _deprecationText(Availability a) => a.deprecated == null
      ? 'Deprecated in the Android SDK'
      : 'Deprecated in Android API ${a.deprecated}';

  static String _docSafe(String s) =>
      s.replaceAll('\n', ' ').replaceAll('\r', ' ').replaceAll('*/', '* /');
}

final class _TypeNames {
  _TypeNames(
    this.methodNames,
    this.fieldNames,
    this.instanceMembers,
    this.conflicts,
  );

  final Map<String, String> methodNames;
  final Map<String, String> fieldNames;
  final Map<String, Set<String>> instanceMembers;
  final Map<String, String> conflicts;
}

final class _MemberContext {
  _MemberContext(this.type, this.name, this.mapper, this.file);

  final ApiType type;
  final String name;
  final DartJniTypeMapper mapper;
  final String file;
}

final class _Resolver implements DartTypeResolver {
  _Resolver(this.emitter, this.namespace);

  final DartJniEmitter emitter;
  final String namespace;
  final usedNamespaces = <String>{};

  @override
  String? qualifiedName(String typeId) {
    final t = emitter._types[typeId];
    if (t == null) return null;
    final n = emitter.dartName(t);
    if (t.namespace == namespace) return n;
    usedNamespaces.add(t.namespace);
    return '${Identifiers.packagePrefix(t.namespace)}.$n';
  }
}
