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
    : module = planJvmTarget(
        module,
        callbacks: options.callbacks,
        suspend: true,
      ) {
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

  /// Namespace / file currently being emitted (cross-package references are
  /// qualified with namespace imports).
  String _ns = '';
  String _file = '';
  final _usedNs = <String>{};

  /// Output path of the module for a Java package.
  static String modulePath(String ns) =>
      'src/generated/${ns.isEmpty ? r'$default' : ns.replaceAll('.', '/')}.ts';

  /// Reference to a generated class from the current module.
  String _ref(ApiType t) {
    if (t.namespace == _ns) return _tsName(t);
    _usedNs.add(t.namespace);
    return '${Identifiers.packagePrefix(t.namespace)}.${_tsName(t)}';
  }

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
      ..._tsFiles(),
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

  /// JavaScript/TypeScript globals and runtime names a generated class must
  /// not shadow inside the bindings module.
  static const _tsGlobals = {
    'Error',
    'TypeError',
    'RangeError',
    'Array',
    'Number',
    'Boolean',
    'Symbol',
    'Set',
    'Map',
    'WeakMap',
    'WeakSet',
    'WeakRef',
    'Promise',
    'Date',
    'Math',
    'JSON',
    'RegExp',
    'Proxy',
    'Reflect',
    'Iterator',
    'Iterable',
    'Record',
    'Readonly',
    'Partial',
    'Pick',
    'Required',
    'ArrayBuffer',
    'DataView',
    'BigInt',
    'Intl',
    'String',
    'Object',
    'Function',
    'Infinity',
    'NaN',
    'Handle',
    'JavaObject',
    'Atomics',
    'Buffer',
    'Event',
    'Element',
    'Node',
    'Uint8Array',
    'Int8Array',
    'Uint16Array',
    'Int16Array',
    'Uint32Array',
    'Int32Array',
    'Float32Array',
    'Float64Array',
    'BigInt64Array',
  };

  void _assignTypeNames() {
    final bySimple = <String, List<ApiType>>{};
    for (final t in _types.values) {
      var simple = Identifiers.dartType(t.qualifiedSimpleName);
      if (_tsGlobals.contains(simple)) simple = '$simple\$';
      (bySimple[simple] ??= []).add(t);
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

  static String _escape(String n, Set<String> reserved) =>
      reserved.contains(n) ? '$n\$' : n;

  // ------------------------------------------------------------- TypeScript

  List<GeneratedFile> _tsFiles() {
    final byNs = SplayTreeMap<String, List<ApiType>>();
    for (final t in _types.values) {
      (byNs[t.namespace] ??= []).add(t);
    }
    final files = <GeneratedFile>[];
    for (final e in byNs.entries) {
      _ns = e.key;
      _file = modulePath(e.key);
      _usedNs.clear();
      final body = StringBuffer();
      for (final t in e.value) {
        _emitBrandType(body, t);
      }
      body.writeln();
      for (final t in e.value) {
        _emitClass(body, t);
        for (final s in _sets.declaredBy(t.id)) {
          if (_setNames.containsKey(s)) _emitConstantSet(body, s);
        }
      }
      _emitContextHelpers(body);
      final out = StringBuffer(generatedHeader(module))
        ..writeln('/* eslint-disable */')
        ..writeln()
        ..writeln(
          "import * as \$rt from '${_relative(_file, 'src/runtime.ts')}';",
        )
        ..writeln(
          "import {JavaObject} from '${_relative(_file, 'src/runtime.ts')}';",
        );
      for (final ns in _usedNs.toList()..sort()) {
        out.writeln(
          "import * as ${Identifiers.packagePrefix(ns)} from '${_relative(_file, modulePath(ns))}';",
        );
      }
      out
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
        ..writeln()
        ..write(body.toString().trimRight())
        ..writeln();
      files.add(GeneratedFile(_file, out.toString()));
    }
    final index = StringBuffer(generatedHeader(module))..writeln();
    for (final ns in byNs.keys) {
      index.writeln(
        "export * from '${_relative('src/generated/index.ts', modulePath(ns))}';",
      );
    }
    files.add(GeneratedFile('src/generated/index.ts', index.toString()));
    return files;
  }

  static String _relative(String from, String to) {
    final fromParts = from.split('/')..removeLast();
    final toParts = to.split('/');
    var i = 0;
    while (i < fromParts.length &&
        i < toParts.length - 1 &&
        fromParts[i] == toParts[i]) {
      i++;
    }
    final up = List.filled(fromParts.length - i, '..');
    final rel = [...up, ...toParts.sublist(i)].join('/');
    final noExt = rel.endsWith('.ts') ? rel.substring(0, rel.length - 3) : rel;
    return noExt.startsWith('.') ? noExt : './$noExt';
  }

  void _emitContextHelpers(StringBuffer b) {
    final ctx = _types['android.content.Context'];
    if (ctx != null && ctx.namespace == _ns) {
      final n = _tsName(ctx);
      b
        ..writeln()
        ..writeln(
          '/** The application `Context` (requires `NabContext.init(application)` in Java). */',
        )
        ..writeln('export function applicationContext(): $n {')
        ..writeln(
          "  return \$rt.wrapNonNull($n, \$rt.applicationContextHandle(), 'NabContext.applicationContext()');",
        )
        ..writeln('}');
    }
    final act = _types['android.app.Activity'];
    if (act != null && act.namespace == _ns) {
      final n = _tsName(act);
      b
        ..writeln()
        ..writeln(
          '/** The current `Activity`, or null. Use synchronously; activities are short-lived. */',
        )
        ..writeln('export function currentActivity(): $n | null {')
        ..writeln('  return \$rt.wrap($n, \$rt.currentActivityHandle());')
        ..writeln('}');
    }
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
    if (m.isBytes) {
      base = 'Uint8Array | number[]';
    } else if (m.isPrimitive || m.wrapClass == null) {
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
    if (m.isBytes) return '\$rt.bytesArg($name)';
    if (m.isPrimitive || m.wrapClass == null) return name;
    if (m.arrayDepth > 0) return '\$rt.hArray($name)';
    return '\$rt.h($name)';
  }

  String _convertReturn(String raw, TypeRef t, TsJsiType m, String symbol) {
    final nonnull = t.nullability == Nullability.nonnull;
    if (m.isPrimitive) return '$raw as ${m.tsType}';
    if (m.isBytes) {
      return nonnull
          ? "nn(\$rt.bytesResult($raw), '$symbol')"
          : '\$rt.bytesResult($raw)';
    }
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
      for (var i = 0; i < n.parameters.length; i++) {
        final s = _sets.forParameter(n.id, i);
        if (s != null && _setNames.containsKey(s)) {
          lines.add(
            '- `${Identifiers.typescript(n.parameters[i].name)}`: one of `${_setNames[s]}`${s.flag ? ' (flags)' : ''}',
          );
        }
      }
      final rs = _sets.forReturn(n.id);
      if (rs != null && _setNames.containsKey(rs)) {
        lines.add(
          '- Result: one of `${_setNames[rs]}`${rs.flag ? ' (flags)' : ''}',
        );
      }
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

  final _namesCache = <String, _RnNames>{};

  /// `@IntDef`/`@LongDef`/`@StringDef` constant sets (TRD §61).
  late final ConstantSets _sets = ConstantSets.of(module);

  /// TS names of the emitted constant sets (`Owner$Name`); sets whose name
  /// would clash with a generated declaration, or whose `long` values are not
  /// exact JavaScript numbers in ergonomic mode, are documented only.
  late final Map<ConstantSet, String> _setNames = () {
    final taken = <String>{
      for (final n in _tsNames.values) ...[n, '$n\$Like', '$n\$Impl'],
    };
    return {
      for (final s in _sets.all)
        if (_types.containsKey(s.owner.id) &&
            !taken.contains('${_tsName(s.owner)}\$${s.name}') &&
            s.members.every((f) => _tsLiteral(f.constantValue!) != null) &&
            (s.kind != 'long' ||
                options.mode == TypescriptMode.strict ||
                s.members.every((f) => _safeInt(f.constantValue!.literal))))
          s: '${_tsName(s.owner)}\$${s.name}',
    };
  }();

  /// `as const` object of a constant set, plus (unless it holds flags) a
  /// union type of its values. Values are the SDK constants.
  void _emitConstantSet(StringBuffer b, ConstantSet s) {
    final name = _setNames[s]!;
    final ann = switch (s.kind) {
      'int' => 'IntDef',
      'long' => 'LongDef',
      _ => 'StringDef',
    };
    final uses = s.usages.toList()..sort();
    b.writeln();
    b.writeln('/**');
    b.writeln(
      ' * Typed `@$ann` constants of `${s.owner.id}`${s.flag ? ' (flags: combine with `|`)' : ''}. Values are the SDK constants.',
    );
    b.writeln(' * Used by:');
    for (final u in uses.take(8)) {
      b.writeln(' * - `${u.replaceAll('*/', '* /')}`');
    }
    if (uses.length > 8) b.writeln(' * - and ${uses.length - 8} more');
    b.writeln(' */');
    b.writeln('export const $name = {');
    for (final f in s.members) {
      b.writeln('  ${f.name}: ${_tsLiteral(f.constantValue!)},');
    }
    b.writeln('} as const;');
    if (!s.flag) {
      b.writeln('/** One of the values of {@link $name}. */');
      b.writeln('export type $name = (typeof $name)[keyof typeof $name];');
    }
    _bindings.add(
      BindingMapEntry(
        symbolId: '${s.owner.id}\$${s.name}<constants>',
        generated: name,
        file: _file,
        generator: _generatorId,
        runtimeAdapter: 'typed constants (@$ann)',
      ),
    );
  }

  /// The union type typing [m]'s result in ergonomic mode (non-flag sets
  /// only), qualified for the current module; null otherwise.
  String? _setReturnType(ApiMethod m) {
    if (options.mode != TypescriptMode.ergonomic) return null;
    final s = _sets.forReturn(m.id);
    if (s == null || s.flag) return null;
    final n = _setNames[s];
    if (n == null) return null;
    if (s.owner.namespace == _ns) return n;
    _usedNs.add(s.owner.namespace);
    return '${Identifiers.packagePrefix(s.owner.namespace)}.$n';
  }

  /// Instance member names for [t]: declared members get names over the
  /// visible overload set; overrides keep the ancestor's name so prototype
  /// inheritance (see `$rt.inherit`) overrides correctly.
  _RnNames _names(ApiType t) {
    final cached = _namesCache[t.id];
    if (cached != null) return cached;
    final r = _RnNames();
    final inheritedName = <String, String>{};
    final inheritedAsync = <String, String>{};
    final mergeOrder = <String>[];
    for (final s in [?t.superClass, ...t.interfaces]) {
      final st = _types[(s as DeclaredTypeRef).name];
      if (st == null) continue;
      final sn = _names(st);
      for (final e in sn.visibleMethods.entries) {
        if (r.visibleMethods.containsKey(e.key)) continue;
        r.visibleMethods[e.key] = e.value;
        inheritedName[e.key] = sn.keyToName[e.key]!;
        final a = sn.keyToAsync[e.key];
        if (a != null) inheritedAsync[e.key] = a;
        mergeOrder.add(e.key);
      }
      sn.visibleFields.forEach(
        (k, v) => r.visibleFields.putIfAbsent(k, () => v),
      );
      sn.fieldToName.forEach((k, v) => r.fieldToName.putIfAbsent(k, () => v));
      sn.visibleProperties.forEach(
        (k, v) => r.visibleProperties.putIfAbsent(k, () => v),
      );
    }
    final declared =
        t.methods
            .where((m) => m.isGeneratable && !m.isStatic && !m.isConstructor)
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final declaredKeys = {for (final m in declared) _key(m)};
    for (final m in declared) {
      r.visibleMethods[_key(m)] = (m, t);
    }

    // Candidate names: overrides keep the inherited name.
    final candidate = <String, String>{...inheritedName};
    final fresh = declared
        .where((m) => !inheritedName.containsKey(_key(m)))
        .toList();
    final assigned = OverloadNamer.assign(
      r.visibleMethods.values.map((e) => e.$1),
    );

    // Resolve name collisions between different keys (multiple inheritance
    // can bring different overloads under one name). Declared keys win, then
    // merge order; losers are renamed and forwarded explicitly.
    final taken = <String>{};
    final byName = <String, List<String>>{};
    for (final k in [
      ...declaredKeys.where(inheritedName.containsKey),
      ...mergeOrder,
    ]) {
      (byName[candidate[k]!] ??= []).add(k);
    }
    final ordered = byName.keys.toList()..sort();
    for (final name in ordered) {
      final keys = byName[name]!.toSet().toList();
      final winner = keys.first;
      r.keyToName[winner] = name;
      taken.add(name);
      if (keys.length > 1 && !declaredKeys.contains(winner)) {
        r.forwarded.add(winner);
      }
      for (final loser in keys.skip(1)) {
        final m = r.visibleMethods[loser]!.$1;
        var renamed = _escape(
          '${Identifiers.dartMember(m.name)}\$${OverloadNamer.suffix(m)}',
          _instanceReserved,
        );
        while (taken.contains(renamed) || byName.containsKey(renamed)) {
          renamed = '$renamed\$';
        }
        taken.add(renamed);
        r.keyToName[loser] = renamed;
        if (!declaredKeys.contains(loser)) r.forwarded.add(loser);
      }
    }
    for (final m in fresh) {
      var name = _escape(assigned[m.id]!, _instanceReserved);
      while (!taken.add(name)) {
        name = '$name\$';
      }
      r.keyToName[_key(m)] = name;
    }
    // Promise variants.
    for (final k in r.keyToName.keys.toList()..sort()) {
      final m = r.visibleMethods[k]!.$1;
      if (!_asyncAllowed(m)) continue;
      final inherited = inheritedAsync[k];
      if (inherited != null && inheritedName[k] == r.keyToName[k]) {
        r.keyToAsync[k] = inherited;
        taken.add(inherited);
      }
    }
    for (final k in r.keyToName.keys.toList()..sort()) {
      final m = r.visibleMethods[k]!.$1;
      if (!_asyncAllowed(m) || r.keyToAsync.containsKey(k)) continue;
      var a = '${r.keyToName[k]}Async';
      while (!taken.add(a)) {
        a = '$a\$';
      }
      r.keyToAsync[k] = a;
    }
    for (final m in declared) {
      r.declaredMethods[m.id] = r.keyToName[_key(m)]!;
      final a = r.keyToAsync[_key(m)];
      if (a != null) r.declaredAsync[m.id] = a;
    }
    final methodNames = r.keyToName.values.toSet();
    for (final f
        in t.fields.where((f) => f.isGeneratable && !f.isStatic).toList()
          ..sort((a, b) => a.name.compareTo(b.name))) {
      final inherited = r.fieldToName[f.name];
      var name =
          inherited ??
          _escape(
            methodNames.contains(f.name) ? '${f.name}\$field' : f.name,
            _instanceReserved,
          );
      if (inherited == null) {
        while (!taken.add(name)) {
          name = '$name\$';
        }
      }
      r.fieldToName[f.name] = name;
      r.visibleFields[f.name] = (f, t);
      r.declaredFields[f.id] = name;
    }
    // Bean properties: accessors over getX/isX + setX, only where the name
    // is free (not a method, Promise variant, field or reserved name).
    final memberNames = {
      ...r.keyToName.values,
      ...r.keyToAsync.values,
      ...r.fieldToName.values,
    };
    // Own members (e.g. a public field) shadow inherited properties.
    r.visibleProperties.removeWhere((k, _) => memberNames.contains(k));
    for (final bp in beanProperties(t)) {
      final name = bp.name;
      if (memberNames.contains(name) ||
          _instanceReserved.contains(name) ||
          Identifiers.typescript(name) != name) {
        continue;
      }
      r.visibleProperties[name] = (bp, t);
      r.declaredProperties[name] = bp;
    }
    return _namesCache[t.id] = r;
  }

  void _emitClass(StringBuffer b, ApiType t) {
    final n = _tsName(t);
    final names = _names(t);
    _doc(b, t, '', note: 'Kind: ${t.kind.name.replaceAll('Type', '')}');
    // Type-only declaration merging: brands for nominal-ish typing plus the
    // signatures of inherited members, which are copied onto the prototype
    // at load time by `$rt.inherit` (nothing here is emitted as code; React
    // Native's Babel preset rejects `declare` fields).
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
    final declaredKeys = {
      for (final m in t.methods.where(
        (m) => m.isGeneratable && !m.isStatic && !m.isConstructor,
      ))
        _key(m),
    };
    final inheritedMethods =
        names.visibleMethods.entries
            .where((e) => !declaredKeys.contains(e.key))
            .toList()
          ..sort(
            (a, b) =>
                names.keyToName[a.key]!.compareTo(names.keyToName[b.key]!),
          );
    for (final e in inheritedMethods) {
      final (m, owner) = e.value;
      final sig = _signature(owner, m);
      b.writeln('  /** Inherited from `${owner.id}`: `${m.id}` */');
      b.writeln('  ${names.keyToName[e.key]}${sig.params}: ${sig.ret};');
      final asyncName = names.keyToAsync[e.key];
      if (asyncName != null) {
        b.writeln('  $asyncName${sig.params}: Promise<${sig.ret}>;');
      }
    }
    final declaredFieldNames = {
      for (final f in t.fields.where((f) => f.isGeneratable && !f.isStatic))
        f.name,
    };
    for (final e
        in names.visibleFields.entries
            .where((e) => !declaredFieldNames.contains(e.key))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final (f, owner) = e.value;
      final m = _mapper.map(f.type, typeVariableBounds: _typeVars(owner, null));
      b.writeln('  /** Inherited from `${owner.id}`: `${f.id}` */');
      b.writeln(
        '  ${f.isFinal ? 'readonly ' : ''}${names.fieldToName[e.key]}: ${_returnType(f.type, m)};',
      );
    }
    for (final e
        in names.visibleProperties.entries
            .where((e) => !names.declaredProperties.containsKey(e.key))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      final (bp, owner) = e.value;
      final m = _mapper.map(
        bp.getter.returnType,
        typeVariableBounds: _typeVars(owner, bp.getter),
      );
      b.writeln(
        '  /** Inherited bean property of `${owner.id}` (`${bp.getter.name}`${bp.setter == null ? '' : '/`${bp.setter!.name}`'}) */',
      );
      b.writeln(
        '  ${_beanSetterName(owner, bp, _names(owner)) == null ? 'readonly ' : ''}${e.key}: ${_returnType(bp.getter.returnType, m)};',
      );
    }
    b.writeln('}');
    b.writeln('export class $n extends JavaObject {');
    b.writeln(
      "  static readonly javaInternalName: string = '${t.id.replaceAll('.', '/')}';",
    );
    b.writeln(
      "  /** @internal */ static readonly \$t = \$rt.classTable('${t.id}');",
    );
    final anc = _ancestors(t);
    if (anc.isNotEmpty) {
      // Evaluated on first instantiation (after all modules are loaded), so
      // import cycles between package modules are harmless.
      b.writeln(
        '  /** @internal */ static readonly \$anc = (): Array<{prototype: object}> => [${anc.map(_ref).join(', ')}];',
      );
    }
    _bindings.add(
      BindingMapEntry(
        symbolId: t.id,
        generated: n,
        file: _file,
        generator: _generatorId,
        runtimeAdapter: 'JSI class table',
      ),
    );

    // Static fields and constants.
    final staticUsed = <String>{};
    String staticName(String base) {
      var name = _escape(base, _staticReserved);
      while (!staticUsed.add(name)) {
        name = '$name\$';
      }
      return name;
    }

    for (final f
        in t.fields.where((f) => f.isGeneratable && f.isStatic).toList()
          ..sort((a, b) => a.name.compareTo(b.name))) {
      _emitStaticField(b, t, f, staticName(f.name));
    }
    // Constructors.
    final ctors = t.methods
        .where((m) => m.isGeneratable && m.isConstructor)
        .toList();
    final ctorNames = OverloadNamer.assign(ctors);
    for (final m in ctors..sort((a, b) => a.id.compareTo(b.id))) {
      _emitMethod(
        b,
        t,
        t,
        m,
        staticName(ctorNames[m.id]!.isEmpty ? 'new' : ctorNames[m.id]!),
        isStatic: true,
        ctor: true,
      );
    }
    // Static methods.
    final statics = t.methods
        .where((m) => m.isGeneratable && m.isStatic)
        .toList();
    final staticNames = OverloadNamer.assign(statics);
    for (final m
        in statics
          ..sort((a, b) => staticNames[a.id]!.compareTo(staticNames[b.id]!))) {
      final name = staticName(staticNames[m.id]!);
      _emitMethod(b, t, t, m, name, isStatic: true);
      if (_asyncAllowed(m)) {
        _emitMethod(
          b,
          t,
          t,
          m,
          staticName('${name}Async'),
          isStatic: true,
          async: true,
        );
      }
    }
    // Declared instance fields.
    for (final f
        in t.fields.where((f) => f.isGeneratable && !f.isStatic).toList()
          ..sort((a, b) => a.name.compareTo(b.name))) {
      _emitInstanceField(b, t, t, f, names.declaredFields[f.id]!);
    }
    // Declared instance methods (+ Promise variants).
    final declared =
        t.methods
            .where((m) => m.isGeneratable && !m.isStatic && !m.isConstructor)
            .toList()
          ..sort(
            (a, b) => names.declaredMethods[a.id]!.compareTo(
              names.declaredMethods[b.id]!,
            ),
          );
    for (final m in declared) {
      _emitMethod(b, t, t, m, names.declaredMethods[m.id]!, isStatic: false);
      final a = names.declaredAsync[m.id];
      if (a != null) _emitMethod(b, t, t, m, a, isStatic: false, async: true);
    }
    // Bean properties (backed by the native getter/setter methods above).
    for (final e
        in names.declaredProperties.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      _emitBeanProperty(b, t, e.value, e.key, names);
    }
    // Inherited members whose name collides across supertypes are forwarded
    // explicitly (own properties win over prototype copies).
    for (final k in names.forwarded.toList()..sort()) {
      final (m, owner) = names.visibleMethods[k]!;
      _emitMethod(b, t, owner, m, names.keyToName[k]!, isStatic: false);
      final a = names.keyToAsync[k];
      if (a != null) {
        _emitMethod(b, t, owner, m, a, isStatic: false, async: true);
      }
    }
    final visible = [
      for (final e in names.visibleMethods.entries) (e.value.$1, e.value.$2),
    ]..sort((x, y) => x.$1.id.compareTo(y.$1.id));
    final visibleNames = {
      for (final e in names.visibleMethods.entries)
        e.value.$1.id: names.keyToName[e.key]!,
    };
    if (options.callbacks && t.isInterface && visible.isNotEmpty) {
      _emitImplement(b, t, visible, visibleNames);
    }
    b.writeln('}');
    b.writeln();
    if (options.callbacks && t.isInterface && visible.isNotEmpty) {
      _emitImplInterface(b, t, visible, visibleNames);
    }
  }

  ({String params, String ret}) _signature(ApiType owner, ApiMethod m) {
    final tv = _typeVars(owner, m);
    final used = <String>{};
    final params = <String>[];
    for (final p in m.parameters) {
      var pn = Identifiers.typescript(p.name);
      while (!used.add(pn)) {
        pn = '$pn\$';
      }
      params.add(
        '$pn: ${_paramType(p.type, _mapper.map(p.type, typeVariableBounds: tv))}',
      );
    }
    final isVoid =
        m.returnType is PrimitiveTypeRef &&
        (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;
    final ret = isVoid
        ? 'void'
        : _returnType(
            m.returnType,
            _mapper.map(m.returnType, typeVariableBounds: tv),
          );
    return (params: '(${params.join(', ')})', ret: ret);
  }

  bool _asyncAllowed(ApiMethod m) =>
      !isSuspend(m) &&
      m.threading != Threading.mainThread &&
      m.threading != Threading.uiThread;

  /// Boxed results of suspend functions arrive as JS primitives.
  String? _boxedTs(TypeRef t) => switch (t) {
    DeclaredTypeRef(name: 'java.lang.Boolean') => 'boolean',
    DeclaredTypeRef(name: 'java.lang.Long') =>
      options.mode == TypescriptMode.strict ? 'bigint' : 'number',
    DeclaredTypeRef(
      name: 'java.lang.Integer' ||
          'java.lang.Short' ||
          'java.lang.Byte' ||
          'java.lang.Character' ||
          'java.lang.Float' ||
          'java.lang.Double',
    ) =>
      'number',
    _ => null,
  };

  /// A Kotlin `suspend` function: `Promise<T>` settled when the coroutine
  /// completes (the runtime supplies the continuation; calling convention
  /// `(2, [self], ...args)`).
  void _emitSuspend(
    StringBuffer b,
    ApiType t,
    ApiType owner,
    ApiMethod m,
    String name, {
    required bool isStatic,
  }) {
    final tv = _typeVars(owner, m);
    final params = <String>[];
    final args = <String>[];
    final usedParams = <String>{};
    for (final p in suspendParameters(m)) {
      var pn = Identifiers.typescript(p.name);
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
    final result = suspendResult(m);
    final nonnull = result.nullability == Nullability.nonnull;
    final String retType;
    final String Function(String) convert;
    if (isKotlinUnit(result)) {
      retType = 'void';
      convert = (r) => 'undefined';
    } else if (_boxedTs(result) case final prim?) {
      retType = nonnull ? prim : '$prim | null';
      convert = (r) =>
          nonnull ? "nn($r as $prim | null, '${m.id}')" : '$r as $prim | null';
    } else {
      final rt = _mapper.map(result, typeVariableBounds: tv);
      retType = _returnType(result, rt);
      convert = (r) => _convertReturn(r, result, rt, m.id);
    }
    final raw =
        "${_ref(owner)}.\$t()['${_cppKey(m)}'](${[2, if (!isStatic) 'this.\$h', ...args].join(', ')})";
    _doc(
      b,
      m,
      '  ',
      note: owner.id != t.id ? 'Inherited from `${owner.id}`' : null,
    );
    b.writeln(
      '  ${isStatic ? 'static ' : ''}$name(${params.join(', ')}): Promise<$retType> {',
    );
    b.write(_guard(m));
    b.writeln(
      '    return ($raw as Promise<unknown>).then(r => ${convert('r')});',
    );
    b.writeln('  }');
    if (owner.id == t.id) {
      _bindings.add(
        BindingMapEntry(
          symbolId: m.id,
          generated: '${_tsName(t)}.$name',
          file: _file,
          generator: _generatorId,
          runtimeAdapter:
              'JSI host function -> JNI + NabContinuation (Kotlin suspend -> Promise)',
        ),
      );
    }
  }

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
    if (isSuspend(m) && !ctor) {
      _emitSuspend(b, t, owner, m, name, isStatic: isStatic);
      return;
    }
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
    final ownerName = _ref(owner);
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
      final setType = isVoid ? null : _setReturnType(m);
      if (setType != null) {
        final nullable = retType.endsWith(' | null');
        retType = nullable ? '$setType | null' : setType;
        final base = convert;
        convert = (r) => '(${base(r)}) as $retType';
      }
    }
    if (async) {
      b.writeln(
        '  /** Promise variant of `${m.id}`: the JNI call runs on a background thread. */',
      );
    } else {
      _doc(
        b,
        m,
        '  ',
        note: owner.id != t.id ? 'Inherited from `${owner.id}`' : null,
      );
    }
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
          file: _file,
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
            file: _file,
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
        file: _file,
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
    final o = _ref(owner);
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
          file: _file,
          generator: _generatorId,
          runtimeAdapter: 'JSI host function -> JNI field',
        ),
      );
    }
  }

  /// The TS name of [bp]'s setter, or null when the property is read-only
  /// here: no setter, or one whose parameter type differs from the getter's
  /// (e.g. a nullable getter with a non-null setter).
  String? _beanSetterName(ApiType owner, BeanProperty bp, _RnNames names) {
    final s = bp.setter;
    if (s == null) return null;
    final vars = _typeVars(owner, bp.getter);
    final g = bp.getter.returnType;
    final p = s.parameters.single.type;
    if (_paramType(g, _mapper.map(g, typeVariableBounds: vars)) !=
        _paramType(p, _mapper.map(p, typeVariableBounds: vars))) {
      return null;
    }
    return names.declaredMethods[s.id] ?? names.keyToName[_key(s)];
  }

  void _emitBeanProperty(
    StringBuffer b,
    ApiType t,
    BeanProperty bp,
    String name,
    _RnNames names,
  ) {
    final getter = names.declaredMethods[bp.getter.id];
    if (getter == null) return;
    final m = _mapper.map(
      bp.getter.returnType,
      typeVariableBounds: _typeVars(t, bp.getter),
    );
    final setter = _beanSetterName(t, bp, names);
    b.writeln(
      '  /** Bean property backed by `${bp.getter.name}()`${setter == null ? '' : ' / `${bp.setter!.name}()`'}. */',
    );
    b.writeln('  get $name(): ${_returnType(bp.getter.returnType, m)} {');
    b.writeln('    return this.$getter();');
    b.writeln('  }');
    if (setter != null) {
      b.writeln('  set $name(value: ${_paramType(bp.getter.returnType, m)}) {');
      b.writeln('    this.$setter(value);');
      b.writeln('  }');
    }
    _bindings.add(
      BindingMapEntry(
        symbolId: '${t.id}#$name<property>',
        generated: '${_tsName(t)}.$name',
        file: _file,
        generator: _generatorId,
        runtimeAdapter:
            'TS accessor -> ${bp.getter.name}/${bp.setter?.name ?? '-'}',
      ),
    );
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
        file: _file,
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
      "export * from './src/generated';\n";

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
      '-keep class dev.nativeapibindgen.runtime.** { *; }\n'
      '# Kotlin coroutine classes used reflectively by NabContinuation.\n'
      '-keep interface kotlin.coroutines.Continuation { *; }\n'
      '-keep class kotlin.coroutines.EmptyCoroutineContext { *; }\n'
      '-keep class kotlin.Result\$Failure { *; }\n'
      '-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }\n'
      '${_libraryKeepRules()}';

  /// Library (non-SDK) classes are looked up by name from native code, so
  /// R8 must not rename or remove them.
  String _libraryKeepRules() {
    final ids = [
      for (final t in _types.values)
        if (t.provenance.sourceKind == 'library') t.id,
    ]..sort();
    if (ids.isEmpty) return '';
    return '# Library classes bound by name from native code.\n'
        '${ids.map((id) => '-keep class $id { *; }\n').join()}';
  }

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

final class _RnNames {
  /// Visible instance methods by key (declared + inherited), with owner.
  final visibleMethods = <String, (ApiMethod, ApiType)>{};

  /// Method key -> TS name (consistent across the hierarchy).
  final keyToName = <String, String>{};

  /// Method key -> Promise-variant name.
  final keyToAsync = <String, String>{};

  /// Visible instance fields by Java name.
  final visibleFields = <String, (ApiField, ApiType)>{};

  /// Java field name -> TS name.
  final fieldToName = <String, String>{};

  /// Inherited keys re-declared in the class because of name conflicts.
  final forwarded = <String>{};

  /// Visible bean properties by TS name (declared + inherited), with owner.
  final visibleProperties = <String, (BeanProperty, ApiType)>{};

  /// Bean properties declared (or re-declared) by this type, by TS name.
  final declaredProperties = <String, BeanProperty>{};

  /// Declared method id -> name / async name; declared field id -> name.
  final declaredMethods = <String, String>{};
  final declaredAsync = <String, String>{};
  final declaredFields = <String, String>{};
}

final class _Resolver implements TsTypeResolver {
  _Resolver(this.e);

  final RnJsiEmitter e;

  @override
  String? qualifiedName(String typeId) {
    final t = e._types[typeId];
    return t == null ? null : e._ref(t);
  }
}
