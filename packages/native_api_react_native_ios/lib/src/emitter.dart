import 'dart:collection';
import 'dart:convert';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';

import 'planner.dart';
import 'runtime_sources.g.dart';

const _generatorId = 'react-native-ios/ts-jsi-objc';

/// Runtime member flags (mirror `nab::objc::MemberFlags`).
abstract final class _Flags {
  static const owned = 1;
  static const init = 2;
  static const mainThread = 4;
  static const errorOut = 8;
}

/// Options for [RnObjCEmitter].
final class RnObjCOptions {
  /// Creates options.
  const RnObjCOptions({
    this.minIos = const ApiVersion(15),
    this.mode = TypescriptMode.strict,
    this.mainThreadModules = const {},
    this.linkFrameworks = const [],
  });

  /// Minimum iOS version of the app; newer APIs get runtime guards.
  final ApiVersion minIos;

  /// TypeScript mapping mode: 64-bit integers are `bigint` (strict) or
  /// `number` (ergonomic, lossy beyond ±2^53).
  final TypescriptMode mode;

  /// Additional modules whose members are always invoked on the main
  /// thread. By default the IR decides: main-actor declarations
  /// (`NS_SWIFT_UI_ACTOR`) run on the main thread, everything else on the
  /// calling (JS) thread.
  final Set<String> mainThreadModules;

  /// Frameworks the podspec links so their classes are loaded at runtime
  /// (the configured `platform.ios.frameworks`; header-only modules such as
  /// `UIUtilities` must not be listed).
  final List<String> linkFrameworks;
}

/// Emits the iOS half of a React Native bindings library from Apple IR.
///
/// Output (paths relative to the library directory):
/// * `src/generated/apple/<module>.ts` — one TypeScript class per
///   Objective-C class or protocol, interfaces for structs, constant objects
///   for enums; `ios.ts` re-exports them with the runtime.
/// * `cpp/generated/NabBindingsObjC.cpp` — member tables (selector + JS
///   conversion codes) and struct field names for the Objective-C++ runtime.
/// * runtime files, Codegen spec and `NativeApiBindings.podspec`.
final class RnObjCEmitter {
  /// Creates an emitter; [module] is planned internally.
  RnObjCEmitter(ApiModule module, {this.options = const RnObjCOptions()})
    : module = planTsObjC(module) {
    for (final t in this.module.types) {
      _all[t.id] = t;
      if (t.isGeneratable) _types[t.id] = t;
    }
  }

  /// Planned module.
  final ApiModule module;

  /// Options.
  final RnObjCOptions options;

  final _all = SplayTreeMap<String, ApiType>();
  final _types = SplayTreeMap<String, ApiType>();
  final _bindings = <BindingMapEntry>[];
  late final _resolver = ObjCMemberResolver(
    _all,
    escape: Identifiers.typescript,
    reserved: const {
      // ObjCObject instance members.
      r'$h', 'release', 'dispose', 'isReleased', 'objcClassName',
      'isSameObject', 'toString', 'isKindOf', 'as', 'constructor',
    },
    staticReserved: const {
      // Static members of generated classes and Function built-ins.
      'name', 'length', 'caller', 'arguments', 'prototype', 'objcName',
      'objcProtocol', 'alloc', r'new$', 'isA', 'conformsTo', r'$t', r'$anc',
    },
  );

  // Per-file state.
  String _ns = '';
  String _file = '';
  final _usedNs = SplayTreeSet<String>();

  // C++ tables: class id -> member rows.
  final _tables = SplayTreeMap<String, List<String>>();

  // Block factories: key -> (JS codes, C result type, C parameter types).
  final _blockFactories =
      SplayTreeMap<
        String,
        ({String codes, String ret, List<String> params, String display})
      >();

  bool get _bigint => options.mode == TypescriptMode.strict;

  /// Library path of a module's TypeScript file.
  static String libraryPath(String ns) =>
      'src/generated/apple/${ns.toLowerCase()}.ts';

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
    final header = generatedHeader(module);
    files
      ..add(
        GeneratedFile(
          'src/generated/apple/index.ts',
          '$header\n${[for (final ns in byNs.keys) "export * from './${ns.toLowerCase()}';"].join('\n')}\n',
        ),
      )
      ..add(
        GeneratedFile(
          'ios.ts',
          '$header\n'
              '// iOS entry point: import from \'<library>/ios\'.\n'
              "export * from './src/runtime-objc';\n"
              "export * from './src/generated/apple';\n",
        ),
      )
      ..add(GeneratedFile('cpp/generated/NabBindingsObjC.cpp', _tablesCpp()))
      ..add(GeneratedFile('cpp/generated/NabBlocksObjC.mm', _blocksMm()))
      ..add(GeneratedFile('NativeApiBindings.podspec', _podspec()));
    runtimeSources.forEach(
      (path, text) => files.add(GeneratedFile(path, text)),
    );
    files.sort((a, b) => a.path.compareTo(b.path));
    return GenerationOutput(
      files: files,
      bindings: _bindings,
      module: module,
      diagnostics: const [],
    );
  }

  // ------------------------------------------------------------- naming

  /// TypeScript name: the IR simple name, so a protocol that shares its name
  /// with a class (`NSObject`) is `NSObjectProtocol`.
  static String _typeName(ApiType t) =>
      Identifiers.typescript(t.id.substring(t.id.indexOf('.') + 1));

  static String _prefix(String ns) => 'apple_${ns.toLowerCase()}';

  /// TypeScript reference to a generated type from the current file.
  String _ref(String id, {String suffix = ''}) {
    final t = _types[id];
    if (t == null) return 'ObjCObject';
    if (t.namespace == _ns) return '${_typeName(t)}$suffix';
    _usedNs.add(t.namespace);
    return '${_prefix(t.namespace)}.${_typeName(t)}$suffix';
  }

  bool _isObject(TypeRef t) =>
      t is DeclaredTypeRef &&
      !t.name.startsWith('objc.unsupported') &&
      !const {'objc.SEL', 'objc.Class'}.contains(t.name) &&
      switch (_all[t.name]?.kind) {
        TypeKind.struct || TypeKind.enumType => false,
        _ => true,
      };

  static bool _isString(TypeRef t) =>
      t is DeclaredTypeRef && t.name == 'Foundation.NSString';

  /// The primitive behind [t] (enums resolve to their base), or null.
  PrimitiveKind? _primitive(TypeRef t) {
    if (t is PrimitiveTypeRef) return t.kind;
    if (t is DeclaredTypeRef && _all[t.name]?.kind == TypeKind.enumType) {
      final e = _all[t.name]!;
      return e.fields.isEmpty
          ? PrimitiveKind.long
          : (e.fields.first.type as PrimitiveTypeRef).kind;
    }
    return null;
  }

  static bool _is64(PrimitiveKind k) =>
      k == PrimitiveKind.long || k == PrimitiveKind.uint64;

  /// JS conversion code of a value (see `NabObjCRuntime.h`).
  String _conv(TypeRef t) {
    if (t is BlockTypeRef) return 'B${_blockKey(t)};';
    final k = _primitive(t);
    if (k != null) {
      return switch (k) {
        PrimitiveKind.void_ => 'v',
        PrimitiveKind.boolean => 'z',
        _ when _is64(k) => 'j',
        _ => 'n',
      };
    }
    if (_isString(t)) return 's';
    if (t is DeclaredTypeRef && _all[t.name]?.kind == TypeKind.struct) {
      return 'S${_all[t.name]!.name};';
    }
    return 'o';
  }

  String _numberType(PrimitiveKind k) => switch (k) {
    PrimitiveKind.void_ => 'void',
    PrimitiveKind.boolean => 'boolean',
    _ when _is64(k) => _bigint ? 'bigint' : 'number',
    _ => 'number',
  };

  bool _nullable(TypeRef t) => t.nullability != Nullability.nonnull;

  /// C type of a block value (enums resolve to their base type).
  String _cType(TypeRef t) {
    final k = _primitive(t);
    if (k == null) return 'id';
    return switch (k) {
      PrimitiveKind.void_ => 'void',
      PrimitiveKind.boolean => 'BOOL',
      PrimitiveKind.byte => 'int8_t',
      PrimitiveKind.short => 'int16_t',
      PrimitiveKind.int_ => 'int32_t',
      PrimitiveKind.long => 'int64_t',
      PrimitiveKind.char => 'uint16_t',
      PrimitiveKind.uint8 => 'uint8_t',
      PrimitiveKind.uint16 => 'uint16_t',
      PrimitiveKind.uint32 => 'uint32_t',
      PrimitiveKind.uint64 => 'uint64_t',
      PrimitiveKind.float => 'float',
      PrimitiveKind.double_ => 'double',
    };
  }

  /// Registers the block factory for [b] and returns its key (a hash of the
  /// C signature).
  String _blockKey(BlockTypeRef b) {
    final ret = _cType(b.returnType);
    final params = [for (final p in b.parameters) _cType(p)];
    final sig = '$ret(${params.join(',')})';
    var h = 0xcbf29ce484222325;
    for (final c in utf8.encode(sig)) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final key = (h & 0x7FFFFFFFFFFFFFFF).toRadixString(36);
    _blockFactories.putIfAbsent(
      key,
      () => (
        codes: [
          _conv(b.returnType),
          for (final p in b.parameters) _conv(p),
        ].join(),
        ret: ret,
        params: params,
        display: sig,
      ),
    );
    return key;
  }

  /// TypeScript type of a value; [param] uses brand (`$Like`) types so any
  /// subclass instance is accepted.
  String _tsType(TypeRef t, {bool param = false}) {
    if (t is BlockTypeRef) {
      final ret = _primitive(t.returnType) == PrimitiveKind.void_
          ? 'void'
          : _tsType(t.returnType, param: true);
      final args = [
        for (var i = 0; i < t.parameters.length; i++)
          'a$i: ${_tsType(t.parameters[i])}',
      ];
      final fn = '(${args.join(', ')}) => $ret';
      return _nullable(t) ? '($fn) | null' : fn;
    }
    final k = _primitive(t);
    if (k != null) return _numberType(k);
    if (_isString(t)) return _nullable(t) ? 'string | null' : 'string';
    if (t is DeclaredTypeRef && _all[t.name]?.kind == TypeKind.struct) {
      return _ref(t.name);
    }
    final name = t is DeclaredTypeRef ? t.name : '';
    final base = _types.containsKey(name)
        ? _ref(name, suffix: param ? r'$Like' : '')
        : 'ObjCObject';
    return _nullable(t) ? '$base | null' : base;
  }

  // ------------------------------------------------------------- library

  String _library(String ns, List<ApiType> types) {
    _ns = ns;
    _file = libraryPath(ns);
    _usedNs.clear();
    final body = StringBuffer();
    for (final t in types) {
      switch (t.kind) {
        case TypeKind.enumType:
          _emitEnum(body, t);
        case TypeKind.struct:
          _emitStruct(body, t);
        case TypeKind.classType || TypeKind.protocol:
          _emitClass(body, t);
        default:
          break;
      }
    }
    final b = StringBuffer(generatedHeader(module))
      ..writeln('/* eslint-disable */')
      ..writeln()
      ..writeln("import * as \$rt from '../../runtime-objc';")
      ..writeln("import {ObjCObject} from '../../runtime-objc';");
    for (final other in _usedNs) {
      if (other == ns) continue;
      b.writeln(
        "import * as ${_prefix(other)} from './${other.toLowerCase()}';",
      );
    }
    b
      ..writeln()
      ..write(body.toString().trimRight())
      ..writeln();
    return b.toString();
  }

  void _docLines(StringBuffer b, ApiNode n, String indent, {String? objc}) {
    final lines = <String>[
      if (objc != null) 'Objective-C: `$objc`' else 'Native API: `${n.id}`',
    ];
    final ios = n.availability.platforms['ios'];
    if (ios?.introduced != null) {
      lines.add(
        '- iOS ${ios!.introduced}+${ios.introduced! > options.minIos ? ' (guarded at runtime)' : ''}',
      );
    }
    if (ios?.deprecated != null) {
      lines.add('@deprecated Deprecated in iOS ${ios!.deprecated}');
    }
    for (final d in n.diagnostics.where((d) => d.severity != Severity.error)) {
      lines.add('- Note ${d.code.code} ${d.code.label}: ${d.message}');
    }
    final ref = n.documentation.reference;
    if (ref != null) lines.add('- Reference: $ref');
    if (lines.length == 1) {
      b.writeln('$indent/** ${lines.single} */');
    } else {
      b.writeln('$indent/**');
      for (final l in lines) {
        b.writeln('$indent * ${l.replaceAll('*/', '*\\/')}');
      }
      b.writeln('$indent */');
    }
  }

  void _binding(String id, String generated, String adapter) => _bindings.add(
    BindingMapEntry(
      symbolId: id,
      generated: generated,
      file: _file,
      generator: _generatorId,
      runtimeAdapter: adapter,
    ),
  );

  void _emitEnum(StringBuffer b, ApiType t) {
    final n = _typeName(t);
    final base = _primitive(DeclaredTypeRef(t.id)) ?? PrimitiveKind.long;
    final big = _is64(base) && _bigint;
    _docLines(b, t, '');
    b.writeln('export const $n = {');
    for (final f in t.fields.where((f) => f.isGeneratable)) {
      final v = f.constantValue!.literal;
      b.writeln('  ${Identifiers.typescript(f.name)}: ${big ? '${v}n' : v},');
      _binding(f.id, '$n.${f.name}', 'constant');
    }
    b
      ..writeln('} as const;')
      ..writeln();
    _binding(t.id, n, 'constant object');
  }

  void _emitStruct(StringBuffer b, ApiType t) {
    final n = _typeName(t);
    _docLines(b, t, '');
    b.writeln('export interface $n {');
    for (final f in t.fields) {
      b.writeln('  ${Identifiers.typescript(f.name)}: ${_tsType(f.type)};');
      _binding(f.id, '$n.${f.name}', 'plain object field');
    }
    b
      ..writeln('}')
      ..writeln();
    _binding(t.id, n, 'plain object (struct by value)');
  }

  /// All ancestors (nearest first, superclass chain before protocols).
  List<ApiType> _ancestors(ApiType t) {
    final out = <ApiType>[];
    final seen = <String>{t.id};
    final queue = Queue<ApiType>.of(_resolver.directSupers(t));
    while (queue.isNotEmpty) {
      final s = queue.removeFirst();
      if (!seen.add(s.id)) continue;
      out.add(s);
      queue.addAll(_resolver.directSupers(s));
    }
    return out;
  }

  String _brand(ApiType t) => '__brand_${t.id.replaceAll('.', '_')}';

  void _emitClass(StringBuffer b, ApiType t) {
    final n = _typeName(t);
    final isProtocol = t.kind == TypeKind.protocol;
    final names = _resolver.names(t);
    final ancestors = [
      for (final a in _ancestors(t))
        if (_types.containsKey(a.id)) a,
    ];
    final rows = _tables[t.id] = <String>[];

    b.writeln(
      '/** Any object that is a `${t.name}`${isProtocol ? ' (conforms to the protocol)' : ''}. */',
    );
    b.writeln(
      'export type $n\$Like = ObjCObject & {readonly ${_brand(t)}: true};',
    );
    b.writeln();
    _docLines(
      b,
      t,
      '',
      objc: '${isProtocol ? '@protocol' : '@interface'} ${t.name}',
    );

    // Interface: brands + inherited instance members (implemented at runtime
    // by copying ancestor prototypes, see ensureInherited).
    final declaredNames = {for (final (_, nm) in names.declared) nm};
    b
      ..writeln(
        '// eslint-disable-next-line @typescript-eslint/no-unsafe-declaration-merging',
      )
      ..writeln('export interface $n {')
      ..writeln('  readonly ${_brand(t)}: true;');
    for (final a in ancestors) {
      b.writeln('  readonly ${_brand(a)}: true;');
    }
    final inherited = SplayTreeMap<String, ObjCMember>();
    names.keyToName.forEach((key, name) {
      final m = names.visible[key]!;
      if (m.owner.id == t.id || declaredNames.contains(name)) return;
      if (!_types.containsKey(m.owner.id)) return;
      if (names.conflicts.containsKey(name) &&
          names.conflicts[name]!.key != key) {
        return;
      }
      inherited.putIfAbsent(name, () => m);
    });
    inherited.forEach((name, m) {
      b.writeln('  /** Inherited from `${m.owner.name}`. */');
      if (m.property != null) {
        final getter = _getter(m);
        b.writeln(
          '  ${_setter(m) == null ? 'readonly ' : ''}$name: ${_tsType(getter.returnType)};',
        );
      } else {
        final sig = _params(m.method!);
        final ret = _retType(m.method!);
        b.writeln('  $name(${sig.decl}): $ret;');
        if (!_isInitOrAlloc(m.method!)) {
          b.writeln('  ${name}Async(${sig.decl}): Promise<$ret>;');
        }
      }
    });
    b.writeln('}');

    b.writeln('export class $n extends ObjCObject {');
    b.writeln("  static readonly objcName: string = '${t.name}';");
    if (isProtocol) b.writeln('  static readonly objcProtocol = true;');
    b.writeln(
      "  /** @internal */ static readonly \$t = \$rt.classTable('${t.id}');",
    );
    if (ancestors.isNotEmpty) {
      b.writeln(
        '  /** @internal */ static readonly \$anc = (): Array<{prototype: object}> => [${ancestors.map((a) => _ref(a.id)).join(', ')}];',
      );
    }
    if (isProtocol) {
      b
        ..writeln('  /** Whether [o] conforms to `<${t.name}>`. */')
        ..writeln(
          '  static conformsTo(o: ObjCObject | null | undefined): boolean {',
        )
        ..writeln(
          "    return o !== null && o !== undefined && \$rt.objc().conformsToProtocol(o.\$h, '${t.name}');",
        )
        ..writeln('  }');
    } else {
      final main =
          t.threading == Threading.mainThread ||
              options.mainThreadModules.contains(t.namespace)
          ? _Flags.mainThread
          : 0;
      rows
        ..add(_row('+alloc', 'alloc', 'o', 'ClassMethod', _Flags.owned | main))
        ..add(_row('+new', 'new', 'o', 'ClassMethod', _Flags.owned | main));
      b
        ..writeln('  /** `+alloc` (call an `init…` method next). */')
        ..writeln('  static alloc(): $n {')
        ..writeln(
          "    return \$rt.wrapNonNull($n, $n.\$t()['+alloc'](false), '${t.id}#+alloc');",
        )
        ..writeln('  }')
        ..writeln('  /** `+new` (`[[${t.name} alloc] init]`). */')
        ..writeln('  static new\$(): $n {')
        ..writeln(
          "    return \$rt.wrapNonNull($n, $n.\$t()['+new'](false), '${t.id}#+new');",
        )
        ..writeln('  }')
        ..writeln(
          '  /** Whether [o] is an instance of `${t.name}` (or a subclass). */',
        )
        ..writeln('  static isA(o: ObjCObject | null | undefined): o is $n {')
        ..writeln(
          "    return o !== null && o !== undefined && \$rt.objc().isKindOfClass(o.\$h, '${t.name}');",
        )
        ..writeln('  }');
    }
    for (final (m, name) in names.declared) {
      if (m.property != null) {
        _emitProperty(b, t, m, name, rows);
      } else {
        _emitMethod(b, t, m.method!, name, rows);
      }
    }
    b
      ..writeln('}')
      ..writeln();
    _binding(t.id, n, 'TypeScript class over JSI HostObject');
  }

  static bool _isInitOrAlloc(ApiMethod m) =>
      m.isConstructor ||
      m.name.startsWith('init') ||
      const {'alloc', 'new'}.contains(m.name);

  /// Ownership/thread/error flags of [m] declared in [owner].
  int _flags(ApiType owner, ApiMethod m) {
    var f = 0;
    final family = m.name.replaceFirst(RegExp(r'^_+'), '');
    bool inFamily(String prefix) =>
        family == prefix ||
        (family.startsWith(prefix) &&
            !RegExp('[a-z]').hasMatch(family[prefix.length]));
    if (inFamily('init')) {
      f |= _Flags.init;
    } else if (inFamily('alloc') ||
        inFamily('new') ||
        inFamily('copy') ||
        inFamily('mutableCopy')) {
      f |= _Flags.owned;
    }
    if (m.threading == Threading.mainThread ||
        options.mainThreadModules.contains(owner.namespace)) {
      f |= _Flags.mainThread;
    }
    if (m.parameters.isNotEmpty && isErrorOut(m.parameters.last.type)) {
      f |= _Flags.errorOut;
    }
    return f;
  }

  String _row(
    String key,
    String selector,
    String conv,
    String kind,
    int flags,
  ) =>
      '{${jsonEncode(key)}, ${jsonEncode(selector)}, ${jsonEncode(conv)}, MemberKind::$kind, $flags}';

  ({String decl, String args}) _params(ApiMethod m) {
    final decl = <String>[];
    final args = <String>[];
    final used = <String>{};
    for (var i = 0; i < m.parameters.length; i++) {
      final p = m.parameters[i];
      if (i == m.parameters.length - 1 && isErrorOut(p.type)) continue;
      var pn = Identifiers.typescript(p.name.isEmpty ? 'arg$i' : p.name);
      while (!used.add(pn)) {
        pn = '$pn\$';
      }
      decl.add('$pn: ${_tsType(p.type, param: true)}');
      final bt = p.type;
      if (bt is BlockTypeRef) {
        args.add(_blockAdapter(pn, bt, m.id));
        continue;
      }
      args.add(_isObject(p.type) && !_isString(p.type) ? '\$rt.h($pn)' : pn);
    }
    return (decl: decl.join(', '), args: args.join(', '));
  }

  /// The JS function passed to the runtime for block parameter [pn]: wraps
  /// object arguments in their classes and unwraps an object result.
  String _blockAdapter(String pn, BlockTypeRef b, String symbol) {
    final params = [
      for (var i = 0; i < b.parameters.length; i++) 'a$i: unknown',
    ];
    String arg(int i) {
      final t = b.parameters[i];
      if (_primitive(t) != null) {
        return 'a$i as ${_numberType(_primitive(t)!)}';
      }
      if (_isString(t)) {
        return 'a$i as ${_nullable(t) ? 'string | null' : 'string'}';
      }
      final cls = t is DeclaredTypeRef && _types.containsKey(t.name)
          ? _ref(t.name)
          : 'ObjCObject';
      return _nullable(t)
          ? '\$rt.wrap($cls, a$i)'
          : "\$rt.wrapNonNull($cls, a$i, '$symbol block argument')";
    }

    final call =
        '$pn(${[for (var i = 0; i < b.parameters.length; i++) arg(i)].join(', ')})';
    final r = b.returnType;
    final body = _isObject(r) && !_isString(r) ? '\$rt.h($call)' : call;
    final fn = '(${params.join(', ')}) => $body';
    return _nullable(b) ? '$pn === null ? null : $fn' : fn;
  }

  String _retType(ApiMethod m) {
    if (_primitive(m.returnType) == PrimitiveKind.void_) return 'void';
    return _tsType(m.returnType);
  }

  /// Converts raw value `raw` to the declared TypeScript type.
  String _convertReturn(TypeRef t, String raw, String symbol) {
    final k = _primitive(t);
    if (k != null) {
      return k == PrimitiveKind.void_ ? raw : '$raw as ${_numberType(k)}';
    }
    if (_isString(t)) {
      return _nullable(t)
          ? '$raw as string | null'
          : "\$rt.nonNullString($raw, '$symbol')";
    }
    if (t is DeclaredTypeRef && _all[t.name]?.kind == TypeKind.struct) {
      return '$raw as ${_ref(t.name)}';
    }
    final cls = t is DeclaredTypeRef && _types.containsKey(t.name)
        ? _ref(t.name)
        : 'ObjCObject';
    return _nullable(t)
        ? '\$rt.wrap($cls, $raw)'
        : "\$rt.wrapNonNull($cls, $raw, '$symbol')";
  }

  String _guard(ApiNode n, String indent) {
    final ios = n.availability.platforms['ios'];
    final intro = ios?.introduced;
    if (intro == null || !(intro > options.minIos)) return '';
    return "$indent\$rt.IosApi.require(${intro.major}, ${intro.minor}, ${intro.patch}, '${n.id}');\n";
  }

  void _emitMethod(
    StringBuffer b,
    ApiType t,
    ApiMethod m,
    String name,
    List<String> rows,
  ) {
    final n = _typeName(t);
    final key = '${m.isStatic ? '+' : '-'}${m.name}';
    final conv = StringBuffer(_conv(m.returnType));
    for (var i = 0; i < m.parameters.length; i++) {
      final p = m.parameters[i];
      if (i == m.parameters.length - 1 && isErrorOut(p.type)) continue;
      conv.write(_conv(p.type));
    }
    rows.add(
      _row(
        key,
        m.name,
        conv.toString(),
        m.isStatic ? 'ClassMethod' : 'InstanceMethod',
        _flags(t, m),
      ),
    );
    final sig = _params(m);
    final ret = _retType(m);
    final self = m.isStatic ? '' : ', this.\$h';
    final call = "$n.\$t()['$key']";
    final args = sig.args.isEmpty ? '' : ', ${sig.args}';
    final stat = m.isStatic ? 'static ' : '';
    _docLines(
      b,
      m,
      '  ',
      objc: '${m.isStatic ? '+' : '-'}[${t.name} ${m.name}]',
    );
    b.writeln('  $stat$name(${sig.decl}): $ret {');
    b.write(_guard(m, '    '));
    if (ret == 'void') {
      b.writeln('    $call(false$self$args);');
    } else {
      b.writeln(
        '    return ${_convertReturn(m.returnType, '$call(false$self$args)', m.id)};',
      );
    }
    b.writeln('  }');
    // A block returning a value cannot answer from the background queue a
    // Promise variant runs on.
    final valueBlocks = m.parameters.any(
      (p) =>
          p.type is BlockTypeRef &&
          _primitive((p.type as BlockTypeRef).returnType) !=
              PrimitiveKind.void_,
    );
    if (!_isInitOrAlloc(m) && !valueBlocks) {
      b.writeln(
        '  /** Promise variant of `${m.name}`: runs on ${m.threading == Threading.mainThread || options.mainThreadModules.contains(t.namespace) ? 'the main queue' : 'a background queue'}. */',
      );
      b.writeln('  $stat${name}Async(${sig.decl}): Promise<$ret> {');
      b.write(_guard(m, '    '));
      final conv2 = ret == 'void'
          ? 'undefined'
          : _convertReturn(m.returnType, 'r', m.id);
      b.writeln(
        '    return ($call(true$self$args) as Promise<unknown>).then(${ret == 'void' ? '()' : 'r'} => $conv2);',
      );
      b.writeln('  }');
    }
    _binding(m.id, '$n.$name', 'NSInvocation (JSI HostObject)');
  }

  ApiMethod _getter(ObjCMember m) =>
      m.owner.methods.firstWhere((x) => x.id == m.property!.getterId);

  ApiMethod? _setter(ObjCMember m) {
    final id = m.property!.setterId;
    if (id == null) return null;
    return m.owner.methods
        .where((x) => x.id == id && x.isGeneratable)
        .firstOrNull;
  }

  void _emitProperty(
    StringBuffer b,
    ApiType t,
    ObjCMember m,
    String name,
    List<String> rows,
  ) {
    final n = _typeName(t);
    final p = m.property!;
    final getter = _getter(m);
    final setter = _setter(m);
    final type = getter.returnType;
    final st = m.isStatic ? 'static ' : '';
    final keyBase = ObjCMemberResolver.propertyKey(p);
    rows.add(
      _row(
        keyBase,
        getter.name,
        _conv(type),
        m.isStatic ? 'ClassGetter' : 'InstanceGetter',
        _flags(t, getter),
      ),
    );
    final self = m.isStatic ? '' : ', this.\$h';
    _docLines(
      b,
      getter,
      '  ',
      objc:
          '@property ${p.name} (${setter == null ? 'readonly' : 'readwrite'})',
    );
    b.writeln('  ${st}get $name(): ${_tsType(type)} {');
    b.write(_guard(getter, '    '));
    b.writeln(
      "    return ${_convertReturn(type, "$n.\$t()['$keyBase'](false$self)", getter.id)};",
    );
    b.writeln('  }');
    _binding(getter.id, '$n.$name', 'NSInvocation (property getter)');
    if (setter != null) {
      final vt = setter.parameters.single.type;
      rows.add(
        _row(
          '$keyBase=',
          setter.name,
          'v${_conv(vt)}',
          m.isStatic ? 'ClassSetter' : 'InstanceSetter',
          _flags(t, setter),
        ),
      );
      // Setter and getter types must match in TypeScript: accept the
      // getter's type (plus null when the setter takes nil).
      final getterType = _tsType(type);
      final valueType =
          _nullable(vt) && !getterType.endsWith('| null') && _isObject(vt)
          ? '$getterType | null'
          : getterType;
      final arg = _isObject(vt) && !_isString(vt) ? '\$rt.h(value)' : 'value';
      b.writeln('  ${st}set $name(value: $valueType) {');
      b.write(_guard(setter, '    '));
      b.writeln("    $n.\$t()['$keyBase='](false$self, $arg);");
      b.writeln('  }');
      _binding(setter.id, '$n.$name=', 'NSInvocation (property setter)');
    }
  }

  // ------------------------------------------------------------- C++

  String _tablesCpp() {
    final b = StringBuffer(generatedHeader(module))
      ..writeln(
        '// Member tables consumed by the Objective-C++ runtime (cpp/runtime-objc).',
      )
      ..writeln(
        '// Conversion codes: see NabObjCRuntime.h. The native ABI of every call',
      )
      ..writeln('// comes from the Objective-C runtime (NSMethodSignature).')
      ..writeln('#include "NabObjCRuntime.h"')
      ..writeln()
      ..writeln('#include <cstring>')
      ..writeln('#include <iterator>')
      ..writeln('#include <string>')
      ..writeln()
      ..writeln('namespace nab_generated_objc {')
      ..writeln()
      ..writeln('using nab::objc::ClassSpec;')
      ..writeln('using nab::objc::MemberKind;')
      ..writeln('using nab::objc::MemberSpec;')
      ..writeln('using nab::objc::StructSpec;')
      ..writeln()
      ..writeln('extern const bool kLongAsBigInt;')
      ..writeln('const bool kLongAsBigInt = $_bigint;')
      ..writeln()
      ..writeln('namespace {')
      ..writeln();
    String ident(String id) =>
        'k_${id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}';
    _tables.forEach((id, rows) {
      if (rows.isEmpty) return;
      final sorted = rows.toList()..sort();
      b.writeln('const MemberSpec ${ident(id)}[] = {');
      for (final r in sorted) {
        b.writeln('    $r,');
      }
      b
        ..writeln('};')
        ..writeln();
    });
    b.writeln('const ClassSpec kClasses[] = {');
    _tables.forEach((id, rows) {
      final t = _all[id]!;
      final members = rows.isEmpty
          ? 'nullptr, 0'
          : '${ident(id)}, std::size(${ident(id)})';
      b.writeln(
        '    {${jsonEncode(id)}, ${jsonEncode(t.name)}, ${t.kind == TypeKind.protocol}, $members},',
      );
    });
    b
      ..writeln('};')
      ..writeln();
    final structs = SplayTreeMap<String, ApiType>();
    for (final t in _types.values) {
      if (t.kind == TypeKind.struct) structs[t.name] = t;
    }
    structs.forEach((name, t) {
      b.writeln(
        'const char* const ${ident('f.$name')}[] = {${t.fields.map((f) => jsonEncode(Identifiers.typescript(f.name))).join(', ')}};',
      );
      String fieldStruct(ApiField f) {
        final ft = f.type;
        if (ft is DeclaredTypeRef && _all[ft.name]?.kind == TypeKind.struct) {
          return jsonEncode(_all[ft.name]!.name);
        }
        return 'nullptr';
      }

      b.writeln(
        'const char* const ${ident('s.$name')}[] = {${t.fields.map(fieldStruct).join(', ')}};',
      );
    });
    b.writeln('const StructSpec kStructs[] = {');
    structs.forEach((name, t) {
      b.writeln(
        '    {${jsonEncode(name)}, ${ident('f.$name')}, ${ident('s.$name')}, ${t.fields.length}},',
      );
    });
    if (structs.isEmpty) b.writeln('    {"", nullptr, nullptr, 0},');
    b
      ..writeln('};')
      ..writeln()
      ..writeln('} // namespace')
      ..writeln()
      ..writeln('const ClassSpec* lookupClass(const std::string& key) {')
      ..writeln('  std::size_t lo = 0;')
      ..writeln('  std::size_t hi = std::size(kClasses);')
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
      ..writeln('const StructSpec* lookupStruct(const std::string& name) {')
      ..writeln('  std::size_t lo = 0;')
      ..writeln('  std::size_t hi = ${structs.length};')
      ..writeln('  while (lo < hi) {')
      ..writeln('    const std::size_t mid = (lo + hi) / 2;')
      ..writeln(
        '    const int c = std::strcmp(kStructs[mid].name, name.c_str());',
      )
      ..writeln('    if (c == 0) return &kStructs[mid];')
      ..writeln('    if (c < 0) {')
      ..writeln('      lo = mid + 1;')
      ..writeln('    } else {')
      ..writeln('      hi = mid;')
      ..writeln('    }')
      ..writeln('  }')
      ..writeln('  return nullptr;')
      ..writeln('}')
      ..writeln()
      ..writeln('} // namespace nab_generated_objc');
    return b.toString();
  }

  String _blocksMm() {
    final b = StringBuffer(generatedHeader(module))
      ..writeln(
        '// Objective-C block factories: one per native block signature. Each block',
      )
      ..writeln(
        '// boxes its arguments and forwards to the JavaScript function (see',
      )
      ..writeln('// NabObjCBlocks.h). Compiled with ARC.')
      ..writeln('#import "NabObjCBlocks.h"')
      ..writeln()
      ..writeln('#include <cstring>')
      ..writeln('#include <iterator>')
      ..writeln()
      ..writeln('namespace nab_generated_objc {')
      ..writeln()
      ..writeln('using nab::objc::BlockFactory;')
      ..writeln('using nab::objc::BlockTarget;')
      ..writeln()
      ..writeln('namespace {')
      ..writeln();
    String box(String c, String v) => c == 'id' ? v : '@($v)';
    String unbox(String c, String r) => switch (c) {
      'void' => '',
      'id' => r,
      'BOOL' => '[$r boolValue]',
      'float' || 'double' => '($c)[$r doubleValue]',
      'uint64_t' => '[$r unsignedLongLongValue]',
      _ => '($c)[$r longLongValue]',
    };
    _blockFactories.forEach((key, f) {
      final params = [
        for (var i = 0; i < f.params.length; i++) '${f.params[i]} a$i',
      ].join(', ');
      b
        ..writeln('// ${f.display}')
        ..writeln('id make_$key(std::shared_ptr<BlockTarget> t) {')
        ..writeln('  return [^${f.ret}($params) {')
        ..writeln('    std::vector<id> args;')
        ..writeln('    args.reserve(${f.params.length});');
      for (var i = 0; i < f.params.length; i++) {
        b.writeln('    args.push_back(${box(f.params[i], 'a$i')});');
      }
      if (f.ret == 'void') {
        b.writeln('    nab::objc::callBlock(t, std::move(args));');
      } else {
        b
          ..writeln('    id r = nab::objc::callBlock(t, std::move(args));')
          ..writeln('    return ${unbox(f.ret, 'r')};');
      }
      b
        ..writeln('  } copy];')
        ..writeln('}')
        ..writeln();
    });
    b.writeln('const BlockFactory kBlocks[] = {');
    _blockFactories.forEach((key, f) {
      b.writeln('    {"$key", "${f.codes}", &make_$key},');
    });
    if (_blockFactories.isEmpty) b.writeln('    {"", "", nullptr},');
    b
      ..writeln('};')
      ..writeln()
      ..writeln('} // namespace')
      ..writeln()
      ..writeln('const BlockFactory* lookupBlock(const std::string& key) {')
      ..writeln('  std::size_t lo = 0;')
      ..writeln('  std::size_t hi = ${_blockFactories.length};')
      ..writeln('  while (lo < hi) {')
      ..writeln('    const std::size_t mid = (lo + hi) / 2;')
      ..writeln('    const int c = std::strcmp(kBlocks[mid].key, key.c_str());')
      ..writeln('    if (c == 0) return &kBlocks[mid];')
      ..writeln('    if (c < 0) {')
      ..writeln('      lo = mid + 1;')
      ..writeln('    } else {')
      ..writeln('      hi = mid;')
      ..writeln('    }')
      ..writeln('  }')
      ..writeln('  return nullptr;')
      ..writeln('}')
      ..writeln()
      ..writeln('} // namespace nab_generated_objc');
    return b.toString();
  }

  String _podspec() {
    final frameworks = [for (final f in options.linkFrameworks) "'$f'"];
    final header = generatedHeader(module, comment: '#');
    return '''
$header
# CocoaPods spec for the iOS half of the generated bindings library. Add to
# ios/Podfile:   pod 'NativeApiBindings', :path => '../<library dir>'
# and register the Turbo Module provider in package.json codegenConfig:
#   "ios": {"modulesProvider": {"NativeApiBindgen": "NabModuleProvider"}}
Pod::Spec.new do |s|
  s.name = 'NativeApiBindings'
  s.version = '${ProjectInfo.runtimeVersion.replaceAll('-dev.', '.')}'
  s.summary = 'native-api-bindgen bindings generated from the local iOS SDK (local-only).'
  s.homepage = 'https://example.invalid/native-api-bindings'
  s.license = {:type => 'Apache-2.0'}
  s.authors = 'native-api-bindgen'
  s.platforms = {:ios => '${options.minIos.major}.${options.minIos.minor}'}
  s.source = {:path => '.'}
  s.source_files = [
    'cpp/runtime/NativeApiBindgen.{h,cpp}',
    'cpp/runtime-objc/*.{h,mm}',
    'cpp/generated/NabBindingsObjC.cpp',
    'cpp/generated/NabBlocksObjC.mm',
  ]
  s.frameworks = [${frameworks.join(', ')}]
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_ENABLE_OBJC_ARC' => 'YES',
  }
  install_modules_dependencies(s)
end
''';
  }
}
