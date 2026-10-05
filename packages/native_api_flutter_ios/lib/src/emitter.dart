import 'dart:collection';
import 'dart:convert';

import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';

import 'planner.dart';

const _generatorId = 'flutter-ios/dart-objc';

const _ignores = [
  'camel_case_types',
  'comment_references',
  'constant_identifier_names',
  'deprecated_member_use_from_same_package',
  'invalid_use_of_internal_member',
  'library_prefixes',
  'non_constant_identifier_names',
  'no_leading_underscores_for_local_identifiers',
  'public_member_api_docs',
  'unused_element',
  'unused_import',
  'unused_field',
  'lines_longer_than_80_chars',
  'sort_constructors_first',
];

/// Options for [DartObjCEmitter].
final class DartObjCOptions {
  /// Creates options.
  const DartObjCOptions({this.minIos = const ApiVersion(13)});

  /// Minimum iOS version of the app; newer APIs get runtime guards.
  final ApiVersion minIos;
}

/// Emits Dart bindings over `package:objective_c` from Apple IR (TRD §28).
///
/// Output: `apple/<module>.dart` per framework, `apple/_msgsend.dart` with one
/// typed `objc_msgSend` trampoline per distinct native signature, and the
/// umbrella `apple.dart`. Every Objective-C class/protocol becomes an
/// extension type over `objc.ObjCObject`; there is no registry, so unused
/// declarations are tree-shaken by the Dart AOT compiler.
final class DartObjCEmitter {
  /// Creates an emitter; [module] is planned internally.
  DartObjCEmitter(ApiModule module, {this.options = const DartObjCOptions()})
    : module = planDartObjC(module) {
    for (final t in this.module.types) {
      _all[t.id] = t;
      if (t.isGeneratable && !isRuntimeProvided(t.id)) _types[t.id] = t;
    }
  }

  /// Planned module.
  final ApiModule module;

  /// Options.
  final DartObjCOptions options;

  final _all = SplayTreeMap<String, ApiType>();
  final _types = SplayTreeMap<String, ApiType>();
  final _bindings = <BindingMapEntry>[];
  final _diagnostics = <Diagnostic>[];
  final _trampolines = SplayTreeMap<String, String>();
  final _blocks = SplayTreeMap<String, String>();
  late final _resolver = ObjCMemberResolver(
    _all,
    escape: Identifiers.dartMember,
    reserved: const {
      r'object$',
      'ref',
      'isA',
      'alloc',
      r'new$',
      'as',
      'fromPointer',
    },
  );
  String _ns = '';
  String _file = '';
  final _usedNs = <String>{};
  final _selectors = SplayTreeSet<String>();
  final _classes = SplayTreeSet<String>();

  /// Library path for a module.
  static String libraryPath(String module) =>
      'apple/${module.toLowerCase()}.dart';

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
    files.add(GeneratedFile('apple/_msgsend.dart', _msgSendLibrary()));
    files.add(GeneratedFile('apple/_blocks.dart', _blocksLibrary()));
    files.add(GeneratedFile('apple/_runtime.dart', _runtimeLibrary()));
    final umbrella = StringBuffer(generatedHeader(module))
      ..writeln()
      ..writeln(
        '/// Umbrella library for the generated Apple bindings. Import with a',
      )
      ..writeln(
        '/// prefix (e.g. `as ios`): Objective-C and Flutter share type names.',
      )
      ..writeln('library;')
      ..writeln();
    for (final ns in byNs.keys) {
      umbrella.writeln("export '${libraryPath(ns)}';");
    }
    umbrella.writeln(
      "export 'apple/_runtime.dart' show NativeObjCError, NativeThreadingError, isMainThread, nsDataView, nsDataFromBytes;",
    );
    files.add(GeneratedFile('apple.dart', umbrella.toString()));
    return GenerationOutput(
      files: files,
      bindings: _bindings,
      module: module,
      diagnostics: _diagnostics,
    );
  }

  // --------------------------------------------------------------- names

  String _typeName(ApiType t) => Identifiers.dartType(t.qualifiedSimpleName);

  /// Dart reference to a type from the current library.
  String _ref(String id) {
    if (isRuntimeProvided(id)) {
      return 'objc.${id.substring(id.indexOf('.') + 1)}';
    }
    final t = _types[id];
    if (t == null) return 'objc.ObjCObject';
    if (t.namespace == _ns) return _typeName(t);
    _usedNs.add(t.namespace);
    return '${_prefix(t.namespace)}.${_typeName(t)}';
  }

  static String _prefix(String ns) => 'apple_${ns.toLowerCase()}';

  // ------------------------------------------------------------- library

  String _library(String ns, List<ApiType> types) {
    _ns = ns;
    _file = libraryPath(ns);
    _usedNs.clear();
    _selectors.clear();
    _classes.clear();
    final body = StringBuffer();
    for (final t in types) {
      switch (t.kind) {
        case TypeKind.struct:
          _emitStruct(body, t);
        case TypeKind.enumType:
          _emitEnum(body, t);
        case TypeKind.classType || TypeKind.protocol:
          _emitObjCType(body, t);
        default:
          break;
      }
    }
    final b = StringBuffer(generatedHeader(module))
      ..writeln()
      ..writeln('// ignore_for_file: ${_ignores.join(', ')}')
      ..writeln()
      ..writeln('/// Bindings for the `$ns` module.')
      ..writeln('library;')
      ..writeln()
      ..writeln("import 'dart:async' as async;")
      ..writeln("import 'dart:ffi' as ffi;")
      ..writeln()
      ..writeln("import 'package:objective_c/objective_c.dart' as objc;")
      ..writeln()
      ..writeln("import '_blocks.dart' as bk;")
      ..writeln("import '_msgsend.dart' as ms;")
      ..writeln("import '_runtime.dart' as rt;");
    for (final other in _usedNs.toList()..sort()) {
      b.writeln("import '${other.toLowerCase()}.dart' as ${_prefix(other)};");
    }
    b.writeln();
    for (final c in _classes) {
      b.writeln("final _class_$c = objc.getClass('$c');");
    }
    for (final s in _selectors) {
      b.writeln("final _sel_${_selIdent(s)} = objc.registerName('$s');");
    }
    b
      ..writeln()
      ..write(body.toString().trimRight())
      ..writeln();
    return b.toString();
  }

  static String _selIdent(String s) => s.replaceAll(':', '_');

  String _sel(String s) {
    _selectors.add(s);
    return '_sel_${_selIdent(s)}';
  }

  String _cls(String name) {
    _classes.add(name);
    return '_class_$name';
  }

  // ------------------------------------------------------------- types

  void _docLines(
    StringBuffer b,
    ApiNode n,
    String indent, {
    String? objc,
    String? generatedAs,
  }) {
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
      lines.add('- Deprecated in iOS ${ios!.deprecated}');
    }
    final mac = n.availability.platforms['macos'];
    if (mac != null) {
      lines.add(
        mac.unavailable
            ? '- macOS: unavailable'
            : '- macOS ${mac.introduced ?? '?'}+',
      );
    }
    final threading = switch (n) {
      ApiMethod(:final threading) || ApiType(:final threading) => threading,
      _ => Threading.unspecified,
    };
    if (threading == Threading.mainThread) {
      lines.add(
        '- Threading: main actor (`NS_SWIFT_UI_ACTOR`): call on the main thread (the root isolate on iOS); checked in debug builds',
      );
    } else if (threading == Threading.anyThread) {
      lines.add('- Threading: nonisolated (callable from any thread)');
    }
    for (final d in n.diagnostics) {
      lines.add('- Note ${d.code.code} ${d.code.label}: ${d.message}');
    }
    if (generatedAs != null) lines.add('- Selector mapped to `$generatedAs`');
    if (n.documentation.reference != null) {
      lines.add('- Reference: <${n.documentation.reference}>');
    }
    for (final l in lines) {
      b.writeln('$indent/// $l');
    }
    if (n.isDeprecated && ios?.deprecated != null) {
      b.writeln("$indent@Deprecated('Deprecated in iOS ${ios!.deprecated}')");
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

  void _emitStruct(StringBuffer b, ApiType t) {
    final n = _typeName(t);
    _docLines(b, t, '');
    b.writeln('final class $n extends ffi.Struct {');
    for (final f in t.fields) {
      final (annotation, dart) = _structField(f.type);
      if (annotation != null) b.writeln('  @$annotation()');
      final fn = Identifiers.dartMember(f.name);
      b.writeln('  external $dart $fn;');
      b.writeln();
      _binding(f.id, '$n.$fn', 'dart:ffi Struct field');
    }
    b.writeln('}');
    b.writeln();
    _binding(t.id, n, 'dart:ffi Struct');
  }

  (String?, String) _structField(TypeRef t) {
    final m = _native(t);
    if (t is PrimitiveTypeRef ||
        (t is DeclaredTypeRef && _all[t.name]?.kind == TypeKind.enumType)) {
      return (m.ffi, m.dart);
    }
    return (null, m.dart);
  }

  void _emitEnum(StringBuffer b, ApiType t) {
    final n = _typeName(t);
    _docLines(b, t, '');
    b.writeln('abstract final class $n {');
    for (final f in t.fields.where((f) => f.isGeneratable)) {
      _docLines(b, f, '  ');
      b.writeln(
        '  static const int ${Identifiers.dartMember(f.name)} = ${_intLiteral(f.constantValue!)};',
      );
      _binding(f.id, '$n.${f.name}', 'compile-time constant');
    }
    b.writeln('}');
    b.writeln();
    _binding(t.id, n, 'int constants');
  }

  static String _intLiteral(ConstantValue c) {
    if (c.type == 'uint64') {
      final v = BigInt.parse(c.literal);
      // Dart ints are 64-bit two's complement: write as the signed bit pattern.
      return v.toSigned(64).toString();
    }
    return c.literal;
  }

  void _emitObjCType(StringBuffer b, ApiType t) {
    final n = _typeName(t);
    final names = _resolver.names(t);
    final supers = <String>[
      'objc.ObjCObject',
      for (final s in _resolver.directSupers(t)) _ref(s.id),
    ];
    _docLines(
      b,
      t,
      '',
      objc: t.kind == TypeKind.protocol
          ? '@protocol ${t.name}'
          : '@interface ${t.name}',
    );
    b.writeln(
      'extension type $n._(objc.ObjCObject object\$) implements ${supers.toSet().join(', ')} {',
    );
    b.writeln('  /// Views [other] as `$n` (unchecked; see [isA]).');
    b.writeln('  $n.as(objc.ObjCObject other) : object\$ = other;');
    b.writeln();
    b.writeln('  /// Wraps a raw object pointer.');
    b.writeln(
      '  $n.fromPointer(ffi.Pointer<objc.ObjCObjectImpl> other, {bool retain = false, bool release = false})',
    );
    b.writeln(
      '    : object\$ = objc.ObjCObject(other, retain: retain, release: release);',
    );
    b.writeln();
    if (t.kind == TypeKind.classType) {
      final cls = _cls(t.name);
      b.writeln(
        '  /// Whether [obj] is an instance of `${t.name}` (or a subclass).',
      );
      b.writeln('  static bool isA(objc.ObjCObject? obj) =>');
      b.writeln(
        '      obj == null ? false : ${_tramp('bool', ['ptr'])}(obj.ref.pointer, ${_sel('isKindOfClass:')}, $cls);',
      );
      b.writeln();
      b.writeln('  /// `+alloc` (owned).');
      b.writeln(
        '  static $n alloc() => $n.fromPointer(${_tramp('ptr', const [])}($cls, ${_sel('alloc')}), retain: false, release: true);',
      );
      b.writeln();
      b.writeln('  /// `+new` (owned).');
      b.writeln(
        '  static $n new\$() => $n.fromPointer(${_tramp('ptr', const [])}($cls, ${_sel('new')}), retain: false, release: true);',
      );
    } else {
      b.writeln('  /// Whether [obj] conforms to `<${t.name}>`.');
      b.writeln('  static bool conformsTo(objc.ObjCObject obj) =>');
      b.writeln(
        "      ${_tramp('bool', ['ptr'])}(obj.ref.pointer, ${_sel('conformsToProtocol:')}, objc.getProtocol('${t.name}').cast());",
      );
    }
    _binding(t.id, n, 'package:objective_c ObjCObject');
    for (final (m, name) in names.declared) {
      _emitMember(b, t, m, name);
    }
    for (final e
        in names.conflicts.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key))) {
      b.writeln();
      b.writeln('  // Redeclared: inherited from more than one supertype.');
      _emitMember(b, t, e.value, e.key, redeclared: true);
    }
    b.writeln('}');
    b.writeln();
  }

  // ------------------------------------------------------------- members

  void _emitMember(
    StringBuffer b,
    ApiType t,
    ObjCMember m,
    String name, {
    bool redeclared = false,
  }) {
    b.writeln();
    if (m.property != null) {
      _emitProperty(b, t, m, name, redeclared: redeclared);
    } else {
      _emitMethod(b, t, m.owner, m.method!, name, redeclared: redeclared);
    }
  }

  /// FFI spelling of a pointee type. Value types outside the bindings become
  /// `ffi.Void` (opaque); [tramp] spells structs for the shared trampoline
  /// library (module-prefixed).
  String _pointeeFfi(TypeRef p, bool tramp) {
    switch (p) {
      case PrimitiveTypeRef(kind: PrimitiveKind.void_):
        return 'ffi.Void';
      case PrimitiveTypeRef():
        return _native(p).ffi;
      case PointerTypeRef(:final pointee):
        return 'ffi.Pointer<${_pointeeFfi(pointee, tramp)}>';
      case DeclaredTypeRef(:final name):
        final decl = _all[name];
        if (decl?.kind == TypeKind.enumType) return _native(p).ffi;
        if (decl?.kind == TypeKind.struct) {
          if (!_types.containsKey(name) && !isRuntimeProvided(name)) {
            return 'ffi.Void';
          }
          if (isRuntimeProvided(name)) return 'objc.${decl!.name}';
          return tramp
              ? 'apple_${decl!.namespace.toLowerCase()}.${_typeName(decl)}'
              : _ref(name);
        }
        // An object pointer (`NSError *`): the pointee of `NSError **`.
        return 'ffi.Pointer<objc.ObjCObjectImpl>';
      default:
        return 'ffi.Void';
    }
  }

  /// Native (FFI) and Dart types for a [TypeRef] in a signature.
  ({String ffi, String dart, String kind}) _native(
    TypeRef t, {
    bool tramp = false,
  }) {
    switch (t) {
      case PrimitiveTypeRef(:final kind):
        return switch (kind) {
          PrimitiveKind.void_ => (ffi: 'ffi.Void', dart: 'void', kind: 'void'),
          PrimitiveKind.boolean => (
            ffi: 'ffi.Bool',
            dart: 'bool',
            kind: 'bool',
          ),
          PrimitiveKind.byte => (ffi: 'ffi.Int8', dart: 'int', kind: 'i8'),
          PrimitiveKind.short => (ffi: 'ffi.Int16', dart: 'int', kind: 'i16'),
          PrimitiveKind.int_ => (ffi: 'ffi.Int32', dart: 'int', kind: 'i32'),
          PrimitiveKind.long => (ffi: 'ffi.Int64', dart: 'int', kind: 'i64'),
          PrimitiveKind.char => (ffi: 'ffi.Uint16', dart: 'int', kind: 'u16'),
          PrimitiveKind.uint8 => (ffi: 'ffi.Uint8', dart: 'int', kind: 'u8'),
          PrimitiveKind.uint16 => (ffi: 'ffi.Uint16', dart: 'int', kind: 'u16'),
          PrimitiveKind.uint32 => (ffi: 'ffi.Uint32', dart: 'int', kind: 'u32'),
          PrimitiveKind.uint64 => (ffi: 'ffi.Uint64', dart: 'int', kind: 'u64'),
          PrimitiveKind.float => (
            ffi: 'ffi.Float',
            dart: 'double',
            kind: 'f32',
          ),
          PrimitiveKind.double_ => (
            ffi: 'ffi.Double',
            dart: 'double',
            kind: 'f64',
          ),
        };
      case DeclaredTypeRef(:final name):
        final decl = _all[name];
        if (decl?.kind == TypeKind.enumType) {
          final base = decl!.fields.isEmpty
              ? const PrimitiveTypeRef(PrimitiveKind.long)
              : decl.fields.first.type;
          return _native(base);
        }
        if (decl?.kind == TypeKind.struct) {
          final r = _ref(name);
          return (ffi: r, dart: r, kind: 'S${decl!.name}');
        }
        return (
          ffi: 'ffi.Pointer<objc.ObjCObjectImpl>',
          dart: 'ffi.Pointer<objc.ObjCObjectImpl>',
          kind: 'ptr',
        );
      case PointerTypeRef(:final pointee):
        final inner = _pointeeFfi(pointee, tramp);
        return (
          ffi: 'ffi.Pointer<$inner>',
          dart: 'ffi.Pointer<$inner>',
          kind: 'p($inner)',
        );
      default:
        return (
          ffi: 'ffi.Pointer<objc.ObjCObjectImpl>',
          dart: 'ffi.Pointer<objc.ObjCObjectImpl>',
          kind: 'ptr',
        );
    }
  }

  bool _isObject(TypeRef t) =>
      t is DeclaredTypeRef &&
      _all[t.name]?.kind != TypeKind.enumType &&
      _all[t.name]?.kind != TypeKind.struct;

  /// Dart API type of a parameter / return.
  String _apiType(TypeRef t) {
    if (t is BlockTypeRef) {
      final fn = _blockFnType(t);
      return t.nullability == Nullability.nonnull ? fn : '$fn?';
    }
    if (_isObject(t)) {
      final name = (t as DeclaredTypeRef).name;
      final base = name == 'objc.id' ? 'objc.ObjCObject' : _ref(name);
      return t.nullability == Nullability.nonnull ? base : '$base?';
    }
    return _native(t).dart;
  }

  String _argExpr(String v, TypeRef t) {
    if (t is BlockTypeRef) {
      // [v] is the block variable created before the call.
      return t.nullability == Nullability.nonnull
          ? '$v.ref.pointer.cast<objc.ObjCObjectImpl>()'
          : '$v?.ref.pointer.cast<objc.ObjCObjectImpl>() ?? ffi.nullptr';
    }
    if (!_isObject(t)) return v;
    return t.nullability == Nullability.nonnull
        ? '$v.ref.pointer'
        : '$v?.ref.pointer ?? ffi.nullptr';
  }

  /// Ownership of a returned object per ARC method families.
  static bool _returnsOwned(String selector) {
    final s = selector.startsWith('_') ? selector.substring(1) : selector;
    bool family(String f) =>
        s.startsWith(f) &&
        (s.length == f.length || !RegExp('[a-z]').hasMatch(s[f.length]));
    return family('alloc') ||
        family('new') ||
        family('copy') ||
        family('mutableCopy') ||
        family('init');
  }

  // ------------------------------------------------------------- blocks

  /// Dart API function type of a block: `void Function(bool, NSString?)`.
  String _blockFnType(BlockTypeRef b) {
    final ret = _isVoid(b.returnType) ? 'void' : _blockApiType(b.returnType);
    return '$ret Function(${b.parameters.map(_blockApiType).join(', ')})';
  }

  /// Block argument/result types: objects are nullable unless declared
  /// non-null.
  String _blockApiType(TypeRef t) {
    if (_isObject(t)) {
      final name = (t as DeclaredTypeRef).name;
      final base = name == 'objc.id' ? 'objc.ObjCObject' : _ref(name);
      return t.nullability == Nullability.nonnull ? base : '$base?';
    }
    return _native(t).dart;
  }

  static bool _isVoid(TypeRef t) =>
      t is PrimitiveTypeRef && t.kind == PrimitiveKind.void_;

  static String _exceptional(String ffiType) => switch (ffiType) {
    'ffi.Bool' => 'false',
    'ffi.Float' || 'ffi.Double' => '0.0',
    final x when x.startsWith('ffi.Int') || x.startsWith('ffi.Uint') => '0',
    _ => '',
  };

  /// Registers the block factory for [b] in `_blocks.dart` and returns its
  /// name (`bk.sync_<hash>` / `bk.listener_<hash>`).
  String _blockFactory(BlockTypeRef b, BlockMode mode) {
    final ret = _native(b.returnType, tramp: true);
    final ps = [for (final p in b.parameters) _native(p, tramp: true)];
    final ffiSig =
        '${ret.ffi} Function(${['ffi.Pointer<objc.ObjCBlockImpl>', ...ps.map((p) => p.ffi)].join(', ')})';
    final h = _hash('$ffiSig/${mode.name}');
    final dartParams = [
      for (var i = 0; i < ps.length; i++) '${ps[i].dart} a$i',
    ].join(', ');
    final dartTypes = ps.map((p) => p.dart).join(', ');
    final args = [for (var i = 0; i < ps.length; i++) 'a$i'].join(', ');
    final display = b.display.replaceAll('*/', '* /');
    if (mode == BlockMode.sync) {
      final exc = _exceptional(ret.ffi);
      _blocks.putIfAbsent(
        'sync_$h',
        () =>
            '${ret.dart} _sync_$h(ffi.Pointer<objc.ObjCBlockImpl> block${dartParams.isEmpty ? '' : ', $dartParams'}) =>\n'
            '    (objc.getBlockClosure(block) as ${ret.dart} Function($dartTypes))($args);\n'
            'final _sync_${h}_callable = ffi.Pointer.fromFunction<$ffiSig>(_sync_$h${exc.isEmpty ? '' : ', $exc'}).cast<ffi.Void>();\n'
            '\n'
            '/// Synchronous block `$display`: must be invoked on the creating isolate\'s thread.\n'
            'objc.ObjCBlockBase sync_$h(${ret.dart} Function($dartTypes) fn) => objc.ObjCBlockBase(\n'
            '  objc.newClosureBlock(_sync_${h}_callable, fn, true),\n'
            '  retain: false,\n'
            '  release: true,\n'
            ');\n',
      );
      return 'bk.sync_$h';
    }
    _blocks.putIfAbsent(
      'listener_$h',
      () =>
          '/// Listener block `$display`: callable from any thread; [fn] runs\n'
          '/// asynchronously on the creating isolate. With [once] (completion\n'
          '/// handlers) the callable is closed after the first call.\n'
          'objc.ObjCBlockBase listener_$h(void Function($dartTypes) fn, {bool once = false}) {\n'
          '  late final ffi.NativeCallable<$ffiSig> cb;\n'
          '  cb = ffi.NativeCallable<$ffiSig>.listener((ffi.Pointer<objc.ObjCBlockImpl> block${dartParams.isEmpty ? '' : ', $dartParams'}) {\n'
          '    if (once) cb.close();\n'
          '    fn($args);\n'
          '  });\n'
          '  if (!once) cb.keepIsolateAlive = false;\n'
          '  return objc.ObjCBlockBase(\n'
          '    objc.newPointerBlock(cb.nativeFunction.cast(), ffi.nullptr),\n'
          '    retain: false,\n'
          '    release: true,\n'
          '  );\n'
          '}\n',
    );
    return 'bk.listener_$h';
  }

  /// `final $v = bk.…((native args) => fn(converted));` for block parameter
  /// [pn] of type [b].
  String _blockVar(
    String v,
    String pn,
    BlockTypeRef b,
    BlockMode mode, {
    required bool once,
  }) {
    final factory = _blockFactory(b, mode);
    final ps = [for (final p in b.parameters) _native(p, tramp: true)];
    final nativeParams = [
      for (var i = 0; i < ps.length; i++) '${ps[i].dart} a$i',
    ].join(', ');
    String convertArg(int i) {
      final t = b.parameters[i];
      if (!_isObject(t)) return 'a$i';
      final name = (t as DeclaredTypeRef).name;
      final ref = name == 'objc.id' ? 'objc.ObjCObject' : _ref(name);
      final ctor = ref == 'objc.ObjCObject'
          ? 'objc.ObjCObject'
          : '$ref.fromPointer';
      final make = '$ctor(a$i, retain: true, release: true)';
      return t.nullability == Nullability.nonnull
          ? make
          : '(a$i.address == 0 ? null : $make)';
    }

    final call =
        '$pn(${[for (var i = 0; i < ps.length; i++) convertArg(i)].join(', ')})';
    final String body;
    if (_isVoid(b.returnType)) {
      body = '{ $call; }';
    } else if (_isObject(b.returnType)) {
      body = b.returnType.nullability == Nullability.nonnull
          ? '=> $call.ref.retainAndAutorelease()'
          : '=> $call?.ref.retainAndAutorelease() ?? ffi.nullptr';
    } else {
      body = '=> $call';
    }
    final make =
        '$factory(($nativeParams) $body${mode == BlockMode.listener ? ', once: $once' : ''})';
    return b.nullability == Nullability.nonnull
        ? '    final $v = $make;\n'
        : '    final $v = $pn == null ? null : $make;\n';
  }

  String _blocksLibrary() {
    final b = StringBuffer(generatedHeader(module))
      ..writeln()
      ..writeln('// ignore_for_file: ${_ignores.join(', ')}')
      ..writeln()
      ..writeln(
        '/// Objective-C block factories shared by the generated libraries: one',
      )
      ..writeln(
        '/// per distinct native block signature and creation mode (names are',
      )
      ..writeln('/// signature hashes).')
      ..writeln('library;')
      ..writeln()
      ..writeln("import 'dart:ffi' as ffi;")
      ..writeln()
      ..writeln("import 'package:objective_c/objective_c.dart' as objc;");
    final structs = <String>{};
    for (final body in _blocks.values) {
      for (final m in RegExp(r'apple_(\w+)\.').allMatches(body)) {
        structs.add(m[1]!);
      }
    }
    for (final s in structs.toList()..sort()) {
      b.writeln("import '$s.dart' as apple_$s;");
    }
    b.writeln();
    _blocks.forEach((_, v) => b.writeln(v));
    return b.toString();
  }

  String _wrapReturn(String raw, TypeRef t, String selector) {
    if (!_isObject(t)) return raw;
    final name = (t as DeclaredTypeRef).name;
    final owned = _returnsOwned(selector);
    final ref = name == 'objc.id' ? 'objc.ObjCObject' : _ref(name);
    final ctor = ref == 'objc.ObjCObject'
        ? 'objc.ObjCObject'
        : '$ref.fromPointer';
    final make = '$ctor(\$ret, retain: ${!owned}, release: true)';
    if (t.nullability == Nullability.nonnull) return make;
    return '\$ret.address == 0 ? null : $make';
  }

  /// Registers and returns a typed objc_msgSend trampoline for a signature.
  String _tramp(
    String ret,
    List<String> params, {
    String retFfi = '',
    List<String> paramFfi = const [],
  }) {
    String ffiOf(String k, String explicit) => explicit.isNotEmpty
        ? explicit
        : switch (k) {
            'ptr' => 'ffi.Pointer<objc.ObjCObjectImpl>',
            'bool' => 'ffi.Bool',
            'void' => 'ffi.Void',
            _ => k,
          };
    String dartOf(String ffiType) => switch (ffiType) {
      'ffi.Bool' => 'bool',
      'ffi.Void' => 'void',
      'ffi.Float' || 'ffi.Double' => 'double',
      final x when x.startsWith('ffi.Int') || x.startsWith('ffi.Uint') => 'int',
      final x => x,
    };
    final rf = ffiOf(ret, retFfi);
    final pf = [
      for (var i = 0; i < params.length; i++)
        ffiOf(params[i], i < paramFfi.length ? paramFfi[i] : ''),
    ];
    final sig = '$rf(${pf.join(',')})';
    final name = 'msgSend_${_hash(sig)}';
    final nativeParams = [
      'ffi.Pointer<objc.ObjCObjectImpl>',
      'ffi.Pointer<objc.ObjCSelector>',
      ...pf,
    ].join(', ');
    final dartParams = [
      'ffi.Pointer<objc.ObjCObjectImpl>',
      'ffi.Pointer<objc.ObjCSelector>',
      ...pf.map(dartOf),
    ].join(', ');
    _trampolines.putIfAbsent(
      name,
      () =>
          'final $name = objc.msgSendPointer\n'
          '    .cast<ffi.NativeFunction<$rf Function($nativeParams)>>()\n'
          '    .asFunction<${dartOf(rf)} Function($dartParams)>();\n'
          '\n'
          '/// x86_64 variant (struct return via stret / floating point via fpret).\n'
          'final ${name}V = (${rf.startsWith('ffi.Float') || rf.startsWith('ffi.Double') ? 'objc.msgSendFpretPointer' : 'objc.msgSendStretPointer'})\n'
          '    .cast<ffi.NativeFunction<$rf Function($nativeParams)>>()\n'
          '    .asFunction<${dartOf(rf)} Function($dartParams)>();\n',
    );
    return 'ms.$name';
  }

  /// Needs the x86_64 msgSend variant (stret for structs > 16 bytes, fpret for floats).
  bool _needsVariant(TypeRef ret) {
    if (ret is PrimitiveTypeRef &&
        (ret.kind == PrimitiveKind.float ||
            ret.kind == PrimitiveKind.double_)) {
      return true;
    }
    if (ret is DeclaredTypeRef && _all[ret.name]?.kind == TypeKind.struct) {
      return _structSize(_all[ret.name]!) > 16;
    }
    return false;
  }

  int _structSize(ApiType s) {
    var size = 0;
    for (final f in s.fields) {
      final t = f.type;
      size += switch (t) {
        PrimitiveTypeRef(:final kind) => switch (kind) {
          PrimitiveKind.boolean ||
          PrimitiveKind.byte ||
          PrimitiveKind.uint8 => 1,
          PrimitiveKind.short ||
          PrimitiveKind.uint16 ||
          PrimitiveKind.char => 2,
          PrimitiveKind.int_ ||
          PrimitiveKind.uint32 ||
          PrimitiveKind.float => 4,
          _ => 8,
        },
        DeclaredTypeRef(:final name) when _all[name]?.kind == TypeKind.struct =>
          _structSize(_all[name]!),
        _ => 8,
      };
    }
    return size;
  }

  static String _hash(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in utf8.encode(s)) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    // Dart ints are signed 64-bit: keep 63 bits so names never get a '-'.
    return (h & 0x7FFFFFFFFFFFFFFF).toRadixString(36);
  }

  String _guard(ApiNode n, String label) {
    final ios = n.availability.platforms['ios'];
    final intro = ios?.introduced;
    if (intro == null || !(intro > options.minIos)) return '';
    return '    objc.checkOsVersionInternal(${jsonEncode(label)}, iOS: (false, (${intro.major}, ${intro.minor}, ${intro.patch})));\n';
  }

  /// Debug-only check (inside `assert`, so release builds skip it) for
  /// main-actor members (E013).
  String _mainThreadCheck(ApiMethod m, String label) =>
      m.threading == Threading.mainThread
      ? '    assert(rt.checkMainThread(${jsonEncode(label)}));\n'
      : '';

  /// FFI type spelled for the shared trampoline library (structs prefixed).
  String _trampFfi(TypeRef t) {
    final n = _native(t, tramp: true);
    if (n.kind == 'ptr') return 'ptr';
    if (n.kind.startsWith('S') && t is DeclaredTypeRef) {
      final decl = _all[t.name]!;
      return isRuntimeProvided(t.name)
          ? 'objc.${decl.name}'
          : 'apple_${decl.namespace.toLowerCase()}.${_typeName(decl)}';
    }
    return n.ffi;
  }

  String _call(
    TypeRef ret,
    String target,
    String selector,
    List<(String, TypeRef)> args,
  ) {
    final tramp = _tramp(_trampFfi(ret), [
      for (final (_, t) in args) _trampFfi(t),
    ]);
    final argList = [
      target,
      _sel(selector),
      for (final (v, t) in args) _argExpr(v, t),
    ].join(', ');
    if (_needsVariant(ret)) {
      return 'objc.useMsgSendVariants ? ${tramp}V($argList) : $tramp($argList)';
    }
    return '$tramp($argList)';
  }

  void _emitMethod(
    StringBuffer b,
    ApiType t,
    ApiType owner,
    ApiMethod m,
    String name, {
    bool redeclared = false,
  }) {
    final keywords = objcKeywords(m.name);
    final params = <String>[];
    final named = <String>[];
    final args = <(String, TypeRef)>[];
    final used = <String>{};
    final blockVars = StringBuffer();
    // How each Dart parameter is passed on (for the `…Async` convenience).
    final callArgs = <String>[];
    // Cocoa `NSError **` out-parameter (last): hidden and turned into a
    // thrown `NativeObjCError`.
    final errorOut =
        m.parameters.isNotEmpty && isErrorOutParameter(m.parameters.last.type);
    for (var i = 0; i < m.parameters.length; i++) {
      final p = m.parameters[i];
      if (errorOut && i == m.parameters.length - 1) {
        args.add((r'$err', p.type));
        continue;
      }
      String argVar(String pn) {
        final bt = p.type;
        if (bt is! BlockTypeRef) return pn;
        final mode = blockMode(m, p, _all)!;
        final last = i == m.parameters.length - 1;
        blockVars.write(
          _blockVar(
            '\$b$i',
            pn,
            bt,
            mode,
            once: last && _isCompletionName(p.name),
          ),
        );
        return '\$b$i';
      }

      if (i == 0) {
        final pn = Identifiers.dartMember(p.name.isEmpty ? 'arg0' : p.name);
        used.add(pn);
        params.add('${_apiType(p.type)} $pn');
        args.add((argVar(pn), p.type));
        callArgs.add(pn);
      } else {
        var pn = Identifiers.dartMember(
          i < keywords.length ? keywords[i] : 'arg$i',
        );
        while (!used.add(pn)) {
          pn = '$pn\$';
        }
        final nullable =
            (_isObject(p.type) || p.type is BlockTypeRef) &&
            p.type.nullability != Nullability.nonnull;
        named.add('${nullable ? '' : 'required '}${_apiType(p.type)} $pn');
        args.add((argVar(pn), p.type));
        callArgs.add('$pn: $pn');
      }
    }
    final sigParams = [
      ...params,
      if (named.isNotEmpty) '{${named.join(', ')}}',
    ].join(', ');
    final isVoid =
        m.returnType is PrimitiveTypeRef &&
        (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.void_;
    final ret = isVoid ? 'void' : _apiType(m.returnType);
    final target = m.isStatic
        ? _cls(owner.kind == TypeKind.classType ? owner.name : t.name)
        : (m.isConstructor
              ? 'object\$.ref.retainAndReturnPointer()'
              : 'object\$.ref.pointer');
    final objcSig = '${m.isStatic ? '+' : '-'}[${owner.name} ${m.name}]';
    _docLines(
      b,
      m,
      '  ',
      objc: objcSig,
      generatedAs: name == objcFirstKeyword(m.name) ? null : name,
    );
    b.writeln('  ${m.isStatic ? 'static ' : ''}$ret $name($sigParams) {');
    b.write(_guard(m, '${t.name}.${m.name}'));
    b.write(_mainThreadCheck(m, objcSig));
    b.write(blockVars);
    final call = _call(m.returnType, target, m.name, args);
    if (errorOut) {
      final failed = isVoid
          ? 'true'
          : _isObject(m.returnType)
          ? r'$ret.address == 0'
          : m.returnType is PrimitiveTypeRef &&
                (m.returnType as PrimitiveTypeRef).kind == PrimitiveKind.boolean
          ? r'!$ret'
          : 'true';
      b
        ..writeln(r'    final $err = rt.errorSlot();')
        ..writeln('    try {')
        ..writeln('      ${isVoid ? '' : r'final $ret = '}$call;')
        ..writeln('      rt.throwIfError(\$err, failed: $failed);');
      if (!isVoid) {
        b.writeln(
          '      return ${_isObject(m.returnType) ? _wrapReturn(r'$ret', m.returnType, m.name) : r'$ret'};',
        );
      }
      b
        ..writeln('    } finally {')
        ..writeln(r'      rt.freeErrorSlot($err);')
        ..writeln('    }');
    } else if (isVoid) {
      b.writeln('    $call;');
    } else if (_isObject(m.returnType)) {
      b.writeln('    final \$ret = $call;');
      b.writeln('    return ${_wrapReturn('\$ret', m.returnType, m.name)};');
    } else {
      b.writeln('    return $call;');
    }
    b.writeln('  }');
    if (!redeclared && owner.id == t.id) {
      _binding(
        m.id,
        '${_typeName(t)}.$name',
        'objc_msgSend (package:objective_c)',
      );
    }
    _emitCompletionFuture(b, t, m, name, params, named, callArgs);
  }

  static bool _isCompletionName(String n) =>
      RegExp('(completion|handler|reply)', caseSensitive: false).hasMatch(n);

  /// `Future` convenience for a `void` method whose last parameter is a
  /// completion block: `fooAsync(...)` completes with the block's
  /// argument(s); a trailing `NSError` argument fails the future with
  /// [NativeObjCError] when non-null.
  void _emitCompletionFuture(
    StringBuffer b,
    ApiType t,
    ApiMethod m,
    String name,
    List<String> params,
    List<String> named,
    List<String> callArgs,
  ) {
    if (m.parameters.isEmpty || !_isVoid(m.returnType) || m.isConstructor) {
      return;
    }
    final last = m.parameters.last;
    final bt = last.type;
    if (bt is! BlockTypeRef ||
        !_isVoid(bt.returnType) ||
        !_isCompletionName(last.name)) {
      return;
    }
    final asyncName = '${name}Async';
    final taken = {
      for (final (_, n) in _resolver.names(t).declared) n,
      ..._resolver.names(t).conflicts.keys,
    };
    if (taken.contains(asyncName)) return;
    final values = bt.parameters;
    final hasError =
        values.isNotEmpty &&
        values.last is DeclaredTypeRef &&
        (values.last as DeclaredTypeRef).name == 'Foundation.NSError';
    final results = hasError ? values.sublist(0, values.length - 1) : values;
    final types = [for (final v in results) _blockApiType(v)];
    final T = switch (types.length) {
      0 => 'void',
      1 => types.single,
      _ => '(${types.join(', ')})',
    };
    final vars = [for (var i = 0; i < values.length; i++) 'v$i'];
    final value = switch (results.length) {
      0 => '',
      1 => 'v0',
      _ => '(${[for (var i = 0; i < results.length; i++) 'v$i'].join(', ')})',
    };
    // Drop the block parameter (always last) from the Dart signature.
    final isPositional = m.parameters.length == 1;
    final ps = [...params];
    final ns = [...named];
    final cs = [...callArgs];
    final blockArgName = cs.removeLast();
    if (isPositional) {
      ps.removeLast();
    } else {
      ns.removeLast();
    }
    final sig = [...ps, if (ns.isNotEmpty) '{${ns.join(', ')}}'].join(', ');
    final complete = hasError
        ? '{ final e = v${values.length - 1}; if (e != null) { c.completeError(rt.NativeObjCError.fromNSError(e)); } else { c.complete($value); } }'
        : '{ c.complete($value); }';
    final pass = isPositional
        ? '(${vars.join(', ')}) $complete'
        : '${blockArgName.substring(0, blockArgName.indexOf(':'))}: (${vars.join(', ')}) $complete';
    b.writeln();
    b.writeln(
      '  /// `Future` form of [$name]: completes when `${last.name}` is called.',
    );
    b.writeln(
      '  ${m.isStatic ? 'static ' : ''}async.Future<$T> $asyncName($sig) {',
    );
    b.writeln('    final c = async.Completer<$T>();');
    // Qualified: a parameter may be named like the method.
    final target = m.isStatic ? _typeName(t) : 'this';
    b.writeln('    $target.$name(${[...cs, pass].join(', ')});');
    b.writeln('    return c.future;');
    b.writeln('  }');
  }

  void _emitProperty(
    StringBuffer b,
    ApiType t,
    ObjCMember m,
    String name, {
    bool redeclared = false,
  }) {
    final p = m.property!;
    final owner = m.owner;
    final getter = owner.methods.firstWhere((x) => x.id == p.getterId);
    final setter = p.setterId == null
        ? null
        : owner.methods
              .where((x) => x.id == p.setterId && x.isGeneratable)
              .firstOrNull;
    final type = getter.returnType;
    final isStatic = m.isStatic;
    final target = isStatic
        ? _cls(owner.kind == TypeKind.classType ? owner.name : t.name)
        : 'object\$.ref.pointer';
    _docLines(
      b,
      getter,
      '  ',
      objc: '@property ${p.name} (${p.isReadOnly ? 'readonly' : 'readwrite'})',
    );
    b.writeln('  ${isStatic ? 'static ' : ''}${_apiType(type)} get $name {');
    b.write(_guard(getter, '${t.name}.${p.name}'));
    b.write(
      _mainThreadCheck(
        getter,
        '${isStatic ? '+' : '-'}[${owner.name} ${getter.name}]',
      ),
    );
    final call = _call(type, target, getter.name, const []);
    if (_isObject(type)) {
      b.writeln('    final \$ret = $call;');
      b.writeln('    return ${_wrapReturn('\$ret', type, getter.name)};');
    } else {
      b.writeln('    return $call;');
    }
    b.writeln('  }');
    if (setter != null) {
      final st = setter.parameters.single.type;
      b.writeln();
      b.writeln(
        '  ${isStatic ? 'static ' : ''}set $name(${_apiType(st)} value) {',
      );
      b.write(_guard(setter, '${t.name}.${setter.name}'));
      b.write(
        _mainThreadCheck(
          setter,
          '${isStatic ? '+' : '-'}[${owner.name} ${setter.name}]',
        ),
      );
      b.writeln(
        '    ${_call(const PrimitiveTypeRef(PrimitiveKind.void_), target, setter.name, [('value', st)])};',
      );
      b.writeln('  }');
    }
    if (!redeclared && owner.id == t.id) {
      _binding(
        p.getterId,
        '${_typeName(t)}.$name',
        'objc_msgSend (property getter)',
      );
      if (setter != null) {
        _binding(
          setter.id,
          '${_typeName(t)}.$name=',
          'objc_msgSend (property setter)',
        );
      }
    }
  }

  String _runtimeLibrary() =>
      '''
${generatedHeader(module)}
/// Runtime helpers for the generated Apple bindings.
library;

import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pffi;
import 'package:objective_c/objective_c.dart' as objc;

/// A view of [data]'s bytes without copying. Valid only while [data] is
/// alive and unmodified (`NSData` is immutable; do not use with
/// `NSMutableData` that may be resized). Use `data.toList()` for a copy.
Uint8List nsDataView(objc.NSData data) {
  final n = data.length;
  if (n == 0 || data.bytes.address == 0) return Uint8List(0);
  return data.bytes.cast<ffi.Uint8>().asTypedList(n);
}

/// A new `NSData` holding a copy of [bytes] (one native copy: the buffer is
/// handed to `NSData` with `freeWhenDone`).
objc.NSData nsDataFromBytes(Uint8List bytes) {
  if (bytes.isEmpty) return objc.NSData();
  final buffer = pffi.malloc<ffi.Uint8>(bytes.length);
  buffer.asTypedList(bytes.length).setAll(0, bytes);
  // `dataWithBytesNoCopy:length:` takes ownership and free()s the buffer.
  return objc.NSData.dataWithBytesNoCopy(buffer.cast(), length: bytes.length);
}

/// An Objective-C `NSError` reported through an `NSError **` out-parameter.
final class NativeObjCError implements Exception {
  /// Creates an error.
  const NativeObjCError(this.domain, this.code, this.description);

  /// Copies the fields of [error].
  factory NativeObjCError.fromNSError(objc.NSError error) => NativeObjCError(
    error.domain.toDartString(),
    error.code,
    error.localizedDescription.toDartString(),
  );

  /// `NSError.domain`.
  final String domain;

  /// `NSError.code`.
  final int code;

  /// `NSError.localizedDescription`.
  final String description;

  @override
  String toString() => 'NativeObjCError(\$domain, \$code): \$description';
}

final _pthreadMainNp = ffi.DynamicLibrary.process()
    .lookupFunction<ffi.Int Function(), int Function()>('pthread_main_np');

/// Whether the caller runs on the process's main thread.
bool isMainThread() => _pthreadMainNp() != 0;

/// A main-actor API (`NS_SWIFT_UI_ACTOR`) was called off the main thread
/// (E013 THREADING_CONSTRAINT). Raised by debug-build checks only.
final class NativeThreadingError extends Error {
  /// Creates the error.
  NativeThreadingError(this.symbol);

  /// The Objective-C member, e.g. `-[UIView setAlpha:]`.
  final String symbol;

  @override
  String toString() =>
      'E013 THREADING_CONSTRAINT: \$symbol is main-actor isolated and must be '
      'called on the main thread (the root isolate on iOS)';
}

/// Used as `assert(checkMainThread(...))` before main-actor calls.
bool checkMainThread(String symbol) {
  if (isMainThread()) return true;
  throw NativeThreadingError(symbol);
}

/// Allocates a zeroed `NSError *` slot for an out-parameter.
ffi.Pointer<ffi.Pointer<objc.ObjCObjectImpl>> errorSlot() =>
    pffi.calloc<ffi.Pointer<objc.ObjCObjectImpl>>();

/// Throws [NativeObjCError] when the call [failed] and set the slot.
/// Cocoa only defines the out-parameter when the return value reports
/// failure (`NO` or `nil`), so the slot is ignored otherwise.
void throwIfError(
  ffi.Pointer<ffi.Pointer<objc.ObjCObjectImpl>> slot, {
  required bool failed,
}) {
  if (!failed || slot.value.address == 0) return;
  throw NativeObjCError.fromNSError(
    objc.NSError.fromPointer(slot.value, retain: true, release: true),
  );
}

/// Frees a slot from [errorSlot].
void freeErrorSlot(ffi.Pointer<ffi.Pointer<objc.ObjCObjectImpl>> slot) =>
    pffi.calloc.free(slot);
''';

  String _msgSendLibrary() {
    final b = StringBuffer(generatedHeader(module))
      ..writeln()
      ..writeln('// ignore_for_file: ${_ignores.join(', ')}')
      ..writeln()
      ..writeln(
        '/// Typed `objc_msgSend` trampolines shared by the generated libraries:',
      )
      ..writeln(
        '/// one per distinct native signature (names are signature hashes).',
      )
      ..writeln('library;')
      ..writeln()
      ..writeln("import 'dart:ffi' as ffi;")
      ..writeln()
      ..writeln("import 'package:objective_c/objective_c.dart' as objc;");
    final structs = <String>{};
    for (final body in _trampolines.values) {
      for (final m in RegExp(r'apple_(\w+)\.').allMatches(body)) {
        structs.add(m[1]!);
      }
    }
    for (final s in structs.toList()..sort()) {
      b.writeln("import '$s.dart' as apple_$s;");
    }
    b.writeln();
    _trampolines.forEach((_, v) => b.writeln(v));
    return b.toString();
  }
}
