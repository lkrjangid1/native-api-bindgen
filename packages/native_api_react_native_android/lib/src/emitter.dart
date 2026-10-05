import 'dart:collection';
import 'dart:convert';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';

import 'runtime_sources.g.dart';

const _generatorId = 'react-native-android/ts-jsi';

/// Options for [RnJsiEmitter].
final class RnJsiOptions {
  /// Creates options.
  const RnJsiOptions({
    this.minApi = const ApiVersion(24),
    this.mode = TypescriptMode.strict,
    this.callbacks = true,
  });

  /// Minimum supported API; newer symbols get runtime guards.
  final ApiVersion minApi;

  /// TypeScript mapping mode.
  final TypescriptMode mode;

  /// Generate `implement()` for interfaces.
  final bool callbacks;
}

/// Emits a React Native bindings library from IR (TRD §30–32).
///
/// Output (paths relative to the library directory):
/// * `src/generated/bindings.ts` — one TypeScript class per Java type. All
///   classes live in one module (no import cycles); there is no `extends`
///   between generated classes: inherited instance members are flattened and
///   call the declaring class's table, and parameters use brand types so
///   subclasses are accepted.
/// * `cpp/generated/NabBindings.cpp` — constant member tables (name + JNI
///   descriptor) consumed by the shared C++ runtime; looked up lazily.
/// * runtime files, Codegen spec, CMake fragment, ProGuard rules, README.
final class RnJsiEmitter {
  /// Creates an emitter; [module] is planned for JVM targets internally.
  RnJsiEmitter(ApiModule module, {this.options = const RnJsiOptions()})
    : module = planJvmTarget(module, callbacks: options.callbacks) {
    for (final t in this.module.types) {
      if (t.isGeneratable && t.kind != TypeKind.annotationType) {
        _types[t.id] = t;
      }
    }
    _assignTypeNames();
  }

  /// Planned module.
  final ApiModule module;

  /// Options.
  final RnJsiOptions options;

  final _types = SplayTreeMap<String, ApiType>();
  final _tsNames = <String, String>{};
  final _bindings = <BindingMapEntry>[];
  final _diagnostics = <Diagnostic>[];
  late final TsJsiTypeMapper _mapper = TsJsiTypeMapper(
    _Resolver(this),
    mode: options.mode,
  );

  static const _bindingsFile = 'src/generated/bindings.ts';

  static const _instanceReserved = {
    'constructor',
    'toString',
    'release',
    'dispose',
    'isReleased',
    'javaClassName',
    'javaEquals',
    'javaHashCode',
    'isInstanceOf',
    'as',
    r'$h',
    'valueOf',
    '__proto__',
  };

  static const _staticReserved = {
    'name',
    'length',
    'prototype',
    'caller',
    'arguments',
    'javaInternalName',
    r'$t',
    'implement',
    'constructor',
  };

  /// Generates all files.
  GenerationOutput emit() {
    final files = <GeneratedFile>[
      GeneratedFile(_bindingsFile, _ts()),
      GeneratedFile('cpp/generated/NabBindings.cpp', _cpp()),
      GeneratedFile('index.ts', _index()),
      GeneratedFile('native-api-bindings.cmake', _cmake()),
      GeneratedFile('android/proguard-rules.pro', _proguard()),
      GeneratedFile('README.md', _readme()),
      for (final e in runtimeSources.entries)
        GeneratedFile(e.key, _withHeader(e.key, e.value)),
    ];
    return GenerationOutput(
      files: files,
      bindings: _bindings,
      module: module,
      diagnostics: _diagnostics,
    );
  }

  // ------------------------------------------------------------------ names

  void _assignTypeNames() {
    final bySimple = <String, List<ApiType>>{};
    for (final t in _types.values) {
      (bySimple[Identifiers.dartType(t.qualifiedSimpleName)] ??= []).add(t);
    }
    bySimple.forEach((simple, list) {
      for (final t in list) {
        _tsNames[t.id] = list.length == 1
            ? simple
            : '${Identifiers.packagePrefix(t.namespace)}_$simple';
      }
    });
  }

  String _tsName(ApiType t) => _tsNames[t.id]!;

  static String _brand(String id) =>
      '__brand_${id.replaceAll(RegExp(r'[.$]'), '_')}';

  /// Generated ancestors, nearest first (superclasses then interfaces).
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

  static String _key(ApiMethod m) =>
      '${m.name}${m.id.substring(m.id.indexOf('('))}';

  /// Visible instance methods: declared + inherited (most-derived wins),
  /// each paired with its declaring type.
  List<(ApiMethod, ApiType)> _instanceMethods(ApiType t) {
    final seen = <String>{};
    final out = <(ApiMethod, ApiType)>[];
    for (final owner in [t, ..._ancestors(t)]) {
      for (final m in owner.methods) {
        if (!m.isGeneratable || m.isStatic || m.isConstructor) continue;
        if (seen.add(_key(m))) out.add((m, owner));
      }
    }
    return out;
  }

  List<(ApiField, ApiType)> _instanceFields(ApiType t) {
    final seen = <String>{};
    final out = <(ApiField, ApiType)>[];
    for (final owner in [t, ..._ancestors(t)]) {
      for (final f in owner.fields) {
        if (!f.isGeneratable || f.isStatic) continue;
        if (seen.add(f.name)) out.add((f, owner));
      }
    }
    return out;
  }

  static String _escape(String n, Set<String> reserved) =>
      reserved.contains(n) ? '$n\$' : n;

  // ------------------------------------------------------------- TypeScript

  String _ts() {
    final b = StringBuffer(generatedHeader(module))
      ..writeln('/* eslint-disable */')
      ..writeln()
      ..writeln("import * as \$rt from '../runtime';")
      ..writeln("import {JavaObject} from '../runtime';")
      ..writeln('type Handle = \$rt.Handle;')
      ..writeln()
      ..writeln(
        '/** Thrown by non-null-declared accessors that returned null. */',
      )
      ..writeln('function nn<T>(v: T | null, symbol: string): T {')
      ..writeln(
        '  if (v === null || v === undefined) throw new Error(`\${symbol} returned null although the SDK declares it non-null`);',
      )
      ..writeln('  return v;')
      ..writeln('}')
      ..writeln();
    for (final t in _types.values) {
      _emitBrandType(b, t);
    }
    b.writeln();
    for (final t in _types.values) {
      _emitClass(b, t);
    }
    if (_types.containsKey('android.content.Context')) {
      final n = _tsName(_types['android.content.Context']!);
      b
        ..writeln(
          '/** The application `Context` (requires `NabContext.init(application)` in Java). */',
        )
        ..writeln('export function applicationContext(): $n {')
        ..writeln(
          "  return \$rt.wrapNonNull($n, \$rt.applicationContextHandle(), 'NabContext.applicationContext()');",
        )
        ..writeln('}')
        ..writeln();
    }
    if (_types.containsKey('android.app.Activity')) {
      final n = _tsName(_types['android.app.Activity']!);
      b
        ..writeln(
          '/** The current `Activity`, or null. Use synchronously; activities are short-lived. */',
        )
        ..writeln('export function currentActivity(): $n | null {')
        ..writeln('  return \$rt.wrap($n, \$rt.currentActivityHandle());')
        ..writeln('}')
        ..writeln();
    }
    return '${b.toString().trimRight()}\n';
  }

  void _emitBrandType(StringBuffer b, ApiType t) {
    final n = _tsName(t);
    b.writeln(
      '/** Any object that is a `${t.id}` (subclasses and implementations included). */',
    );
    b.writeln(
      'export type $n\$Like = JavaObject & {readonly ${_brand(t.id)}: true};',
    );
  }

  String _paramType(TypeRef t, TsJsiType m) {
    String base;
    if (m.isPrimitive || m.wrapClass == null) {
      base = m.tsType;
    } else if (m.arrayDepth > 0) {
      base = m.tsType.replaceFirst(
        '(${m.wrapClass} | null)',
        '(${_likeOf(m)} | null)',
      );
    } else {
      base = _likeOf(m);
    }
    if (m.isPrimitive) return base;
    return t.nullability == Nullability.nonnull ? base : '$base | null';
  }

  String _likeOf(TsJsiType m) =>
      m.isOpaque ? 'JavaObject' : '${m.wrapClass}\$Like';

  String _returnType(TypeRef t, TsJsiType m) {
    if (m.isPrimitive) return m.tsType;
    return t.nullability == Nullability.nonnull
        ? m.tsType
        : '${m.tsType} | null';
  }

  String _argExpr(String name, TypeRef t, TsJsiType m) {
    if (m.isPrimitive || m.wrapClass == null) return name;
    if (m.arrayDepth > 0) return '\$rt.hArray($name)';
    return '\$rt.h($name)';
  }

  String _convertReturn(String raw, TypeRef t, TsJsiType m, String symbol) {
    final nonnull = t.nullability == Nullability.nonnull;
    if (m.isPrimitive) return '$raw as ${m.tsType}';
    if (m.wrapClass == null) {
      return nonnull
          ? "nn($raw as ${m.tsType} | null, '$symbol')"
          : '$raw as ${m.tsType} | null';
    }
    if (m.arrayDepth > 0) {
      final e =
          '\$rt.wrapArray(${m.wrapClass}, $raw, ${m.arrayDepth}) as ${m.tsType} | null';
      return nonnull ? "nn($e, '$symbol')" : e;
    }
    return nonnull
        ? "\$rt.wrapNonNull(${m.wrapClass}, $raw, '$symbol')"
        : '\$rt.wrap(${m.wrapClass}, $raw)';
  }

  Map<String, TypeRef> _typeVars(ApiType owner, ApiMethod? m) => {
    for (final p in owner.typeParameters)
      p.name: p.bounds.isEmpty
          ? const DeclaredTypeRef('java.lang.Object')
          : p.bounds.first,
    if (m != null)
      for (final p in m.typeParameters)
        p.name: p.bounds.isEmpty
            ? const DeclaredTypeRef('java.lang.Object')
            : p.bounds.first,
  };

  String _guard(ApiNode n) {
    final intro = n.availability.introduced;
    if (intro == null || !(intro > options.minApi)) return '';
    return "    \$rt.AndroidApi.require(${intro.major}, ${intro.minor}, '${n.id}');\n";
  }

  void _doc(StringBuffer b, ApiNode n, String indent, {String? note}) {
    final lines = <String>['Native API: `${n.id}`'];
    final a = n.availability;
    if (a.introduced != null) {
      lines.add(
        '- Android API: ${a.introduced}+${a.introduced! > options.minApi ? ' (guarded at runtime)' : ''}',
      );
    }
    if (a.deprecated != null) {
      lines.add('- Deprecated in Android API ${a.deprecated}');
    }
    if (n is ApiMethod) {
      if (n.threading != Threading.unspecified) {
        lines.add('- Threading: ${n.threading.name}');
      }
      if (n.permissions.isNotEmpty) {
        lines.add('- Permissions: ${n.permissions.join(', ')}');
      }
      if (n.throws.isNotEmpty) {
        lines.add(
          '- Throws (Java): ${n.throws.map((x) => x.display).join(', ')}; surfaced as NativeJavaError',
        );
      }
    }
    for (final d in n.diagnostics) {
      lines.add(
        '- Note ${d.code.code} ${d.code.label}: ${d.message.replaceAll('*/', '* /')}',
      );
    }
    if (note != null) lines.add('- $note');
    if (n.documentation.reference != null) {
      lines.add('- Reference: ${n.documentation.reference}');
    }
    if (n.isDeprecated) {
      lines.add(
        '@deprecated ${a.deprecated == null ? 'Deprecated in the Android SDK' : 'Deprecated in Android API ${a.deprecated}'}',
      );
    }
    b.writeln('$indent/**');
    for (final l in lines) {
      b.writeln('$indent * $l');
    }
    b.writeln('$indent */');
  }

  void _emitClass(StringBuffer b, ApiType t) {
    final n = _tsName(t);
    _doc(b, t, '', note: 'Kind: ${t.kind.name.replaceAll('Type', '')}');
    // Brands are added via class/interface declaration merging: type-only,
    // nothing is emitted (React Native's Babel preset rejects `declare` fields).
    b.writeln(
      '// eslint-disable-next-line @typescript-eslint/no-unsafe-declaration-merging',
    );
    b.writeln('export interface $n {');
    for (final id in {
      t.id,
      ..._ancestors(t).map((a) => a.id),
    }.toList()..sort()) {
      b.writeln('  readonly ${_brand(id)}: true;');
    }
    b.writeln('}');
    b.writeln('export class $n extends JavaObject {');
    b.writeln(
      "  static readonly javaInternalName: string = '${t.id.replaceAll('.', '/')}';",
    );
    b.writeln(
      "  /** @internal */ static readonly \$t = \$rt.classTable('${t.id}');",
    );
    _bindings.add(
      BindingMapEntry(
        symbolId: t.id,
        generated: n,
        file: _bindingsFile,
        generator: _generatorId,
        runtimeAdapter: 'JSI class table',
      ),
    );

    final instance = _instanceMethods(t);
    final names = OverloadNamer.assign([
      ...instance.map((e) => e.$1),
      ...t.methods.where((m) => m.isGeneratable && m.isStatic),
    ]);
    final instanceNames = <String>{};
    final used = <String>{};
    String unique(String base, Set<String> reserved) {
      var x = _escape(base, reserved);
      while (!used.add(x)) {
        x = '$x\$';
      }
      return x;
    }

    // Static fields and constants.
    final staticUsed = <String>{};
    for (final f
        in t.fields.where((f) => f.isGeneratable && f.isStatic).toList()
          ..sort((a, b) => a.name.compareTo(b.name))) {
      var name = _escape(f.name, _staticReserved);
      while (!staticUsed.add(name)) {
        name = '$name\$';
      }
      _emitStaticField(b, t, f, name);
    }
    // Constructors.
    final ctors = t.methods
        .where((m) => m.isGeneratable && m.isConstructor)
        .toList();
    final ctorNames = OverloadNamer.assign(ctors);
    for (final m in ctors..sort((a, b) => a.id.compareTo(b.id))) {
      var name = ctorNames[m.id]!.isEmpty ? 'new' : ctorNames[m.id]!;
      while (!staticUsed.add(name)) {
        name = '$name\$';
      }
      _emitMethod(b, t, t, m, name, isStatic: true, ctor: true);
    }
    // Static methods.
    for (final m
        in t.methods.where((m) => m.isGeneratable && m.isStatic).toList()
          ..sort((a, b) => names[a.id]!.compareTo(names[b.id]!))) {
      var name = _escape(names[m.id]!, _staticReserved);
      while (!staticUsed.add(name)) {
        name = '$name\$';
      }
      _emitMethod(b, t, t, m, name, isStatic: true);
      final asyncName = '${name}Async';
      if (_asyncAllowed(m) && staticUsed.add(asyncName)) {
        _emitMethod(b, t, t, m, asyncName, isStatic: true, async: true);
      }
    }
    // Instance fields (declared + inherited).
    final methodNameSet = instance.map((e) => names[e.$1.id]!).toSet();
    for (final (f, owner) in _instanceFields(
      t,
    )..sort((a, b) => a.$1.name.compareTo(b.$1.name))) {
      var base = f.name;
      if (methodNameSet.contains(base)) base = '$base\$field';
      final name = unique(base, _instanceReserved);
      instanceNames.add(name);
      _emitInstanceField(b, t, owner, f, name);
    }
    // Instance methods (declared + inherited).
    final ordered = instance.toList()
      ..sort((a, b) => names[a.$1.id]!.compareTo(names[b.$1.id]!));
    final asyncPending = <(ApiMethod, ApiType, String)>[];
    for (final (m, owner) in ordered) {
      final name = unique(names[m.id]!, _instanceReserved);
      _emitMethod(b, t, owner, m, name, isStatic: false);
      if (_asyncAllowed(m)) asyncPending.add((m, owner, '${name}Async'));
    }
    for (final (m, owner, asyncName) in asyncPending) {
      if (used.add(asyncName)) {
        _emitMethod(b, t, owner, m, asyncName, isStatic: false, async: true);
      }
    }
    if (options.callbacks && t.isInterface && instance.isNotEmpty) {
      _emitImplement(b, t, instance, names);
    }
    b.writeln('}');
    b.writeln();
    if (options.callbacks && t.isInterface && instance.isNotEmpty) {
      _emitImplInterface(b, t, instance, names);
    }
  }

  bool _asyncAllowed(ApiMethod m) =>
      m.threading != Threading.mainThread && m.threading != Threading.uiThread;

  String _cppKey(ApiMethod m) => _key(m) + _retDesc(m);

  String _retDesc(ApiMethod m) {
    final d = m.nativeDescriptor ?? '';
    return d.isEmpty ? '' : d.substring(d.indexOf(')') + 1);
  }

  void _emitMethod(
    StringBuffer b,
    ApiType t,
    ApiType owner,
    ApiMethod m,
    String name, {
    required bool isStatic,
    bool ctor = false,
    bool async = false,
  }) {
    final tv = _typeVars(owner, m);
    final params = <String>[];
    final args = <String>[];
    final usedParams = <String>{};
    for (final p in m.parameters) {
      var pn = Identifiers.typescript(p.name);
      // Parameters must not shadow generated classes or module-level helpers.
      if (_tsNames.containsValue(pn) ||
          const {'JavaObject', 'nn', 'Handle'}.contains(pn)) {
        pn = '$pn\$';
      }
      while (!usedParams.add(pn)) {
        pn = '$pn\$';
      }
      final mt = _mapper.map(p.type, typeVariableBounds: tv);
      params.add('$pn: ${_paramType(p.type, mt)}');
      args.add(_argExpr(pn, p.type, mt));
    }
    final ownerName = _tsName(owner);
    final key = ctor
        ? '<init>${m.id.substring(m.id.indexOf('('))}V'
        : _cppKey(m);
    final callArgs = [
      async ? 'true' : 'false',
      if (!isStatic) 'this.\$h',
      ...args,
    ].join(', ');
    final raw = "$ownerName.\$t()['$key']($callArgs)";
    final n = _tsName(t);
    String retType;
    String Function(String) convert;
    if (ctor) {
      retType = n;
      convert = (r) => "\$rt.wrapNonNull($n, $r, '${m.id}')";
    } else {
      final rt = _mapper.map(m.returnType, typeVariableBounds: tv);
      final isVoid =
          m.returnType is PrimitiveTypeRef &&
          (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;
      retType = isVoid ? 'void' : _returnType(m.returnType, rt);
      convert = isVoid
          ? (r) => r
          : (r) => _convertReturn(r, m.returnType, rt, m.id);
    }
    _doc(
      b,
      m,
      '  ',
      note: [
        if (owner.id != t.id) 'Inherited from `${owner.id}`',
        if (async)
          'Runs the JNI call on a background thread; resolves on the JS thread',
      ].join('; ').let((s) => s.isEmpty ? null : s),
    );
    final sig = '${isStatic ? 'static ' : ''}$name(${params.join(', ')})';
    if (async) {
      b.writeln('  $sig: Promise<$retType> {');
      b.write(_guard(m));
      final body = retType == 'void' ? 'undefined' : convert('r');
      b.writeln('    return ($raw as Promise<unknown>).then(r => $body);');
    } else {
      b.writeln('  $sig: $retType {');
      b.write(_guard(m));
      if (retType == 'void') {
        b.writeln('    $raw;');
      } else {
        b.writeln('    return ${convert(raw)};');
      }
    }
    b.writeln('  }');
    if (owner.id == t.id && !async) {
      _bindings.add(
        BindingMapEntry(
          symbolId: m.id,
          generated: '$n.$name',
          file: _bindingsFile,
          generator: _generatorId,
          runtimeAdapter:
              'JSI host function -> JNI (${ctor
                  ? 'NewObjectA'
                  : isStatic
                  ? 'CallStatic*MethodA'
                  : 'Call*MethodA'})',
        ),
      );
    }
  }

  void _emitStaticField(StringBuffer b, ApiType t, ApiField f, String name) {
    final m = _mapper.map(f.type, typeVariableBounds: _typeVars(t, null));
    final cv = f.constantValue;
    if (cv != null && f.isFinal) {
      final lit = _tsLiteral(cv);
      if (lit != null) {
        _doc(
          b,
          f,
          '  ',
          note:
              cv.type == 'long' &&
                  options.mode == TypescriptMode.ergonomic &&
                  !_safeInt(cv.literal)
              ? 'E011 ABI_MISMATCH: value exceeds ±2^53 and loses precision as a number'
              : null,
        );
        b.writeln(
          '  static readonly $name: ${cv.type == 'string' ? 'string' : m.tsType} = $lit;',
        );
        _bindings.add(
          BindingMapEntry(
            symbolId: f.id,
            generated: '${_tsName(t)}.$name',
            file: _bindingsFile,
            generator: _generatorId,
            runtimeAdapter: 'TypeScript constant',
          ),
        );
        return;
      }
    }
    final n = _tsName(t);
    final rt = _returnType(f.type, m);
    _doc(b, f, '  ');
    b.writeln('  static get $name(): $rt {');
    b.write(_guard(f));
    b.writeln(
      "    return ${_convertReturn("$n.\$t()['${f.name}:get'](false)", f.type, m, f.id)};",
    );
    b.writeln('  }');
    if (!f.isFinal) {
      b.writeln('  static set $name(value: ${_paramType(f.type, m)}) {');
      b.writeln(
        "    $n.\$t()['${f.name}:set'](false, ${_argExpr('value', f.type, m)});",
      );
      b.writeln('  }');
    }
    _bindings.add(
      BindingMapEntry(
        symbolId: f.id,
        generated: '$n.$name',
        file: _bindingsFile,
        generator: _generatorId,
        runtimeAdapter: 'JSI host function -> JNI static field',
      ),
    );
  }

  void _emitInstanceField(
    StringBuffer b,
    ApiType t,
    ApiType owner,
    ApiField f,
    String name,
  ) {
    final m = _mapper.map(f.type, typeVariableBounds: _typeVars(owner, null));
    final o = _tsName(owner);
    _doc(
      b,
      f,
      '  ',
      note: owner.id == t.id ? null : 'Inherited from `${owner.id}`',
    );
    b.writeln('  get $name(): ${_returnType(f.type, m)} {');
    b.writeln(
      "    return ${_convertReturn("$o.\$t()['${f.name}:get'](false, this.\$h)", f.type, m, f.id)};",
    );
    b.writeln('  }');
    if (!f.isFinal) {
      b.writeln('  set $name(value: ${_paramType(f.type, m)}) {');
      b.writeln(
        "    $o.\$t()['${f.name}:set'](false, this.\$h, ${_argExpr('value', f.type, m)});",
      );
      b.writeln('  }');
    }
    if (owner.id == t.id) {
      _bindings.add(
        BindingMapEntry(
          symbolId: f.id,
          generated: '${_tsName(t)}.$name',
          file: _bindingsFile,
          generator: _generatorId,
          runtimeAdapter: 'JSI host function -> JNI field',
        ),
      );
    }
  }

  bool _safeInt(String lit) {
    final v = BigInt.tryParse(lit);
    return v != null && v.abs() <= BigInt.from(9007199254740991);
  }

  String? _tsLiteral(ConstantValue cv) {
    switch (cv.type) {
      case 'string':
        return jsonEncode(
          cv.literal,
        ).replaceAll(' ', r' ').replaceAll(' ', r' ');
      case 'boolean':
        return cv.literal;
      case 'long':
        return options.mode == TypescriptMode.strict
            ? '${cv.literal}n'
            : cv.literal;
      case 'int' || 'short' || 'byte' || 'char':
        return cv.literal;
      case 'float' || 'double':
        return switch (cv.literal) {
          'NaN' => 'NaN',
          'Infinity' => 'Infinity',
          '-Infinity' => '-Infinity',
          final s => s,
        };
      default:
        return null;
    }
  }

  // --------------------------------------------------------------- callbacks

  String _implName(ApiType t) => '${_tsName(t)}\$Impl';

  String _callbackParamType(TypeRef t, TsJsiType m) {
    if (m.isPrimitive) return m.tsType;
    if (t is ArrayTypeRef) return 'JavaObject | null';
    return _returnType(t, m);
  }

  void _emitImplInterface(
    StringBuffer b,
    ApiType t,
    List<(ApiMethod, ApiType)> methods,
    Map<String, String> names,
  ) {
    b.writeln(
      '/** JavaScript implementation of `${t.id}`; see [${_tsName(t)}.implement]. */',
    );
    b.writeln('export interface ${_implName(t)} {');
    for (final (m, owner) in methods) {
      final tv = _typeVars(owner, m);
      final params = [
        for (final p in m.parameters)
          '${Identifiers.typescript(p.name)}: ${_callbackParamType(p.type, _mapper.map(p.type, typeVariableBounds: tv))}',
      ];
      final isVoid =
          m.returnType is PrimitiveTypeRef &&
          (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;
      final ret = isVoid
          ? 'void'
          : _paramType(
              m.returnType,
              _mapper.map(m.returnType, typeVariableBounds: tv),
            );
      b.writeln('  /** Implements `${m.id}`. */');
      b.writeln('  ${names[m.id]}(${params.join(', ')}): $ret;');
    }
    b.writeln('}');
    b.writeln();
  }

  void _emitImplement(
    StringBuffer b,
    ApiType t,
    List<(ApiMethod, ApiType)> methods,
    Map<String, String> names,
  ) {
    final n = _tsName(t);
    b.writeln('  /**');
    b.writeln(
      '   * Creates a Java object implementing `${t.id}` backed by [impl].',
    );
    b.writeln(
      '   * `void` methods listed in `options.async` return to Java immediately when',
    );
    b.writeln(
      '   * called from a non-JS thread; other calls from non-JS threads wait for JS.',
    );
    b.writeln('   */');
    b.writeln(
      '  static implement(impl: ${_implName(t)}, options: {async?: Array<keyof ${_implName(t)}>} = {}): $n {',
    );
    b.writeln(
      '    const dispatcher: Record<string, (...args: unknown[]) => unknown> = {',
    );
    final descs = <String, String>{};
    for (final (m, owner) in methods) {
      final tv = _typeVars(owner, m);
      final desc = '${m.name}${m.nativeDescriptor}';
      descs[names[m.id]!] = desc;
      final ps = <String>[];
      final conv = <String>[];
      for (var i = 0; i < m.parameters.length; i++) {
        final p = m.parameters[i];
        final mt = _mapper.map(p.type, typeVariableBounds: tv);
        ps.add('a$i: unknown');
        if (mt.isPrimitive) {
          conv.add('a$i as ${mt.tsType}');
        } else if (p.type is ArrayTypeRef || mt.wrapClass == null) {
          conv.add(
            p.type is ArrayTypeRef
                ? '\$rt.wrap(JavaObject, a$i)'
                : 'a$i as ${mt.tsType}${p.type.nullability == Nullability.nonnull ? '' : ' | null'}',
          );
        } else {
          conv.add(
            p.type.nullability == Nullability.nonnull
                ? "\$rt.wrapNonNull(${mt.wrapClass}, a$i, '${m.id}')"
                : '\$rt.wrap(${mt.wrapClass}, a$i)',
          );
        }
      }
      final isVoid =
          m.returnType is PrimitiveTypeRef &&
          (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;
      final call =
          'impl.${names[m.id]}(${conv.join(', ')}${conv.isEmpty ? '' : ''})';
      final rt = _mapper.map(m.returnType, typeVariableBounds: tv);
      final ret = isVoid || rt.isPrimitive || rt.wrapClass == null
          ? call
          : (m.returnType is ArrayTypeRef
                ? '\$rt.hArray($call)'
                : '\$rt.h($call)');
      b.writeln("      '$desc': (${ps.join(', ')}) =>");
      b.writeln(
        isVoid
            ? "        \$rt.voidCallback('${m.id}', () => $call),"
            : "        \$rt.valueCallback('${m.id}', () => $ret),",
      );
    }
    b.writeln('    };');
    b.writeln('    const descriptors: Record<string, string> = {');
    for (final e in descs.entries) {
      b.writeln("      ${jsonEncode(e.key)}: '${e.value}',");
    }
    b.writeln('    };');
    b.writeln(
      '    const asyncDescriptors = (options.async ?? []).map(k => descriptors[k as string]);',
    );
    b.writeln(
      "    return new $n(\$rt.nab().implement('${t.id.replaceAll('.', '/')}', dispatcher, asyncDescriptors) as Handle);",
    );
    b.writeln('  }');
    _bindings.add(
      BindingMapEntry(
        symbolId: '${t.id}#<implement>',
        generated: '$n.implement',
        file: _bindingsFile,
        generator: _generatorId,
        runtimeAdapter: 'java.lang.reflect.Proxy -> JNI -> CallInvoker',
      ),
    );
  }

  // ------------------------------------------------------------------- C++

  String _cpp() {
    final b = StringBuffer(generatedHeader(module))
      ..writeln(
        '// Member tables consumed by the shared runtime (cpp/runtime/NabRuntime.cpp).',
      )
      ..writeln(
        '// Keys are Java name + JNI descriptor, so they are stable and unique.',
      )
      ..writeln('#include "NabRuntime.h"')
      ..writeln()
      ..writeln('#include <cstring>')
      ..writeln('#include <iterator>')
      ..writeln('#include <string>')
      ..writeln()
      ..writeln('namespace nab_generated {')
      ..writeln()
      ..writeln('using nab::ClassSpec;')
      ..writeln('using nab::MemberKind;')
      ..writeln('using nab::MemberSpec;')
      ..writeln()
      ..writeln('extern const bool kLongAsBigInt;')
      ..writeln(
        'const bool kLongAsBigInt = ${options.mode == TypescriptMode.strict};',
      )
      ..writeln()
      ..writeln('namespace {')
      ..writeln();
    final classes = <(String, String, String?, int)>[];
    for (final t in _types.values) {
      final rows = <String>[];
      final internal = t.id.replaceAll('.', '/');
      for (final m
          in t.methods.where((m) => m.isGeneratable).toList()
            ..sort((a, b) => a.id.compareTo(b.id))) {
        final kind = m.isConstructor
            ? 'Constructor'
            : m.isStatic
            ? 'StaticMethod'
            : 'InstanceMethod';
        final key = m.isConstructor
            ? '<init>${m.id.substring(m.id.indexOf('('))}V'
            : _cppKey(m);
        rows.add(
          '    {"${_cEscape(key)}", "${_cEscape(m.isConstructor ? '<init>' : m.name)}", "${_cEscape(m.nativeDescriptor ?? '')}", MemberKind::$kind},',
        );
      }
      for (final f
          in t.fields.where((f) => f.isGeneratable).toList()
            ..sort((a, b) => a.name.compareTo(b.name))) {
        if (f.constantValue != null && f.isFinal && f.isStatic) continue;
        final s = f.isStatic ? 'Static' : 'Instance';
        rows.add(
          '    {"${f.name}:get", "${f.name}", "${_cEscape(f.nativeDescriptor ?? '')}", MemberKind::${s}Getter},',
        );
        if (!f.isFinal) {
          rows.add(
            '    {"${f.name}:set", "${f.name}", "${_cEscape(f.nativeDescriptor ?? '')}", MemberKind::${s}Setter},',
          );
        }
      }
      final arr = 'k_${t.id.replaceAll(RegExp(r'[.$]'), '_')}';
      if (rows.isNotEmpty) {
        b.writeln('const MemberSpec $arr[] = {');
        rows.forEach(b.writeln);
        b.writeln('};');
        b.writeln();
      }
      classes.add((t.id, internal, rows.isEmpty ? null : arr, rows.length));
    }
    classes.sort((a, b) => a.$1.compareTo(b.$1));
    b.writeln('// Sorted by key (byte order) for binary search.');
    b.writeln('const ClassSpec kClasses[] = {');
    for (final (key, internal, arr, _) in classes) {
      b.writeln(
        '    {"${_cEscape(key)}", "${_cEscape(internal)}", ${arr ?? 'nullptr'}, ${arr == null ? 0 : 'std::size($arr)'}},',
      );
    }
    if (classes.isEmpty) b.writeln('    {"", "", nullptr, 0},');
    b
      ..writeln('};')
      ..writeln()
      ..writeln('} // namespace')
      ..writeln()
      ..writeln('const ClassSpec* lookupClass(const std::string& key) {')
      ..writeln('  std::size_t lo = 0;')
      ..writeln('  std::size_t hi = ${classes.length};')
      ..writeln('  while (lo < hi) {')
      ..writeln('    const std::size_t mid = (lo + hi) / 2;')
      ..writeln(
        '    const int c = std::strcmp(kClasses[mid].key, key.c_str());',
      )
      ..writeln('    if (c == 0) return &kClasses[mid];')
      ..writeln('    if (c < 0) {')
      ..writeln('      lo = mid + 1;')
      ..writeln('    } else {')
      ..writeln('      hi = mid;')
      ..writeln('    }')
      ..writeln('  }')
      ..writeln('  return nullptr;')
      ..writeln('}')
      ..writeln()
      ..writeln('} // namespace nab_generated');
    return b.toString();
  }

  static String _cEscape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  // ------------------------------------------------------------- scaffolding

  String _withHeader(String path, String body) {
    final comment = path.endsWith('.cmake') || path.endsWith('.pro')
        ? '#'
        : '//';
    return '$comment ${ProjectInfo.generatedMarker}\n'
        '$comment Runtime file copied by ${ProjectInfo.name} ${ProjectInfo.generatorVersion}.\n\n$body';
  }

  String _index() =>
      '${generatedHeader(module)}\n'
      "export * from './src/runtime';\n"
      "export * from './src/generated/bindings';\n";

  String _cmake() =>
      '${generatedHeader(module, comment: '#')}\n'
      '# Include from android/app/src/main/jni/CMakeLists.txt after the React Native\n'
      '# application include:  include(<path>/native-api-bindings/native-api-bindings.cmake)\n'
      'set(NAB_DIR \${CMAKE_CURRENT_LIST_DIR})\n'
      'target_sources(\${CMAKE_PROJECT_NAME} PRIVATE\n'
      '    \${NAB_DIR}/cpp/runtime/NabRuntime.cpp\n'
      '    \${NAB_DIR}/cpp/runtime/NativeApiBindgen.cpp\n'
      '    \${NAB_DIR}/cpp/generated/NabBindings.cpp)\n'
      'target_include_directories(\${CMAKE_PROJECT_NAME} PUBLIC \${NAB_DIR}/cpp/runtime)\n';

  String _proguard() =>
      '${generatedHeader(module, comment: '#')}\n'
      '# The runtime classes are only referenced from native code.\n'
      '-keep class dev.nativeapibindgen.runtime.** { *; }\n';

  String _readme() =>
      '# native-api-bindings (generated)\n\n'
      'Generated by ${ProjectInfo.name} ${ProjectInfo.generatorVersion} from Android API ${module.sdkVersion}. '
      'Do not edit; regenerate with `native-api-bindgen generate react-native`.\n\n'
      '## One-time app integration (React Native New Architecture)\n\n'
      '1. `package.json`: `"codegenConfig": {"name": "NabSpecs", "type": "modules", "jsSrcsDir": "<this dir>/specs", '
      '"android": {"javaPackageName": "dev.nativeapibindgen.specs"}}`\n'
      '2. Copy React Native\'s default `CMakeLists.txt` and `OnLoad.cpp` into `android/app/src/main/jni/` '
      '(see reactnative.dev pure C++ modules), add `include(<this dir>/native-api-bindings.cmake)`, and in `OnLoad.cpp`:\n'
      '   - `#include <NativeApiBindgen.h>` and `#include <NabRuntime.h>`\n'
      '   - in `cxxModuleProvider`: `if (name == NativeApiBindgen::kModuleName) return std::make_shared<NativeApiBindgen>(jsInvoker);`\n'
      '   - in `JNI_OnLoad` (inside `facebook::jni::initialize`): `nab::initialize(vm);`\n'
      '3. `android/app/build.gradle`: `externalNativeBuild { cmake { path "src/main/jni/CMakeLists.txt" } }`, '
      '`sourceSets { main { java.srcDirs += ["<this dir>/android/java"] } }`, and add `android/proguard-rules.pro` to `proguardFiles`.\n'
      '4. `MainApplication.onCreate`: `dev.nativeapibindgen.runtime.NabContext.init(this)`.\n\n'
      'Then `import {Intent, applicationContext} from \'<this dir>\';`\n';
}

extension on String {
  T let<T>(T Function(String) f) => f(this);
}

final class _Resolver implements TsTypeResolver {
  _Resolver(this.e);

  final RnJsiEmitter e;

  @override
  String? qualifiedName(String typeId) {
    final t = e._types[typeId];
    return t == null ? null : e._tsName(t);
  }
}
