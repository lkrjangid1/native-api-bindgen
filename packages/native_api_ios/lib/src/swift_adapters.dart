import 'dart:collection';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_ir/native_api_ir.dart';

import 'swift_symbol_graph.dart';

/// Swift standard/Foundation types that bridge to Objective-C.
const _bridged = <String, ({String objc, bool object})>{
  's:Si': (objc: 'NSInteger', object: false), // Int
  's:Su': (objc: 'NSUInteger', object: false), // UInt
  's:Sd': (objc: 'double', object: false), // Double
  's:Sf': (objc: 'float', object: false), // Float
  's:Sb': (objc: 'BOOL', object: false), // Bool
  's:SS': (objc: 'NSString', object: true), // String
  's:10Foundation4DateV': (objc: 'NSDate', object: true),
  's:10Foundation4DataV': (objc: 'NSData', object: true),
  's:10Foundation3URLV': (objc: 'NSURL', object: true),
};

/// Swift keywords that must be escaped with backticks as identifiers.
const _swiftKeywords = {
  'associatedtype',
  'class',
  'deinit',
  'enum',
  'extension',
  'fileprivate',
  'func',
  'import',
  'init',
  'inout',
  'internal',
  'let',
  'open',
  'operator',
  'private',
  'precedencegroup',
  'protocol',
  'public',
  'rethrows',
  'static',
  'struct',
  'subscript',
  'typealias',
  'var',
  'break',
  'case',
  'catch',
  'continue',
  'default',
  'defer',
  'do',
  'else',
  'fallthrough',
  'for',
  'guard',
  'if',
  'in',
  'repeat',
  'return',
  'throw',
  'switch',
  'where',
  'while',
  'Any',
  'as',
  'await',
  'false',
  'is',
  'nil',
  'self',
  'Self',
  'super',
  'throws',
  'true',
  'try',
};

/// `NSObject` members an adapter (an `NSObject` subclass) cannot redeclare.
const _nsObjectMembers = {
  'description',
  'debugDescription',
  'hash',
  'hashValue',
  'isEqual',
  'copy',
  'mutableCopy',
  'self',
  'class',
  'superclass',
  'isProxy',
  'retain',
  'release',
  'autorelease',
  'retainCount',
  'zone',
  'wrapped',
  // Class-side NSObject selectors (static members and enum cases).
  'new',
  'alloc',
  'init',
  'initialize',
  'load',
  'allocWithZone',
  'copyWithZone',
  'instancesRespondToSelector',
  'conformsToProtocol',
};

String _ident(String name) => _swiftKeywords.contains(name) ? '`$name`' : name;

/// Argument labels may be keywords except `inout`, `var` and `let`.
String _label(String label) =>
    const {'inout', 'var', 'let'}.contains(label) ? '`$label`' : label;

/// The `@objc` adapter layer for one Swift module (Layer 2, TRD §22):
/// generated Swift source, the matching Objective-C interface (consumed by
/// the regular Objective-C pipeline), and the module's Swift API
/// as IR with a reason for everything that was not adapted.
final class SwiftAdapterOutput {
  SwiftAdapterOutput._(this.swift, this.header, this.module);

  /// `<Module>Adapters.swift`.
  final String swift;

  /// `<Module>Adapters.h` (binding generation input; not compiled).
  final String header;

  /// Swift API of the module with support decisions (coverage, why-skipped).
  final ApiModule module;
}

/// Plans and emits `@objc` adapters for the Objective-C-representable subset
/// of a Swift module's public API. Adapters wrap values (`wrapped`), so
/// object identity is not preserved across calls.
final class SwiftAdapterGenerator {
  /// Creates a generator for [graph]; [types] limits adaptation to those
  /// type names (all public types when empty).
  SwiftAdapterGenerator(
    this.graph, {
    this.types = const [],
    this.sdkVersion = 'unknown',
    this.importModule = true,
    this.minIos = '15.0',
  });

  /// Symbol graph.
  final SwiftModuleGraph graph;

  /// Selected types (empty: all).
  final List<String> types;

  /// SDK version for provenance.
  final String sdkVersion;

  /// Whether the adapter source imports the module (false when compiled in
  /// the same target).
  final bool importModule;

  /// Deployment target: newer APIs get `@available` / `API_AVAILABLE`.
  final String minIos;

  late final Map<String, SwiftTypeDecl> _byUsr = {
    for (final t in graph.types) t.usr: t,
  };

  /// Selected enums with an `Int` or `String` raw value: usr -> raw type usr.
  /// Their values cross the adapter as the raw value.
  Map<String, String> _enums = const {};

  /// Raw type usr of [t] (from its synthesized `rawValue`), or null.
  static String? _rawType(SwiftTypeDecl t) {
    if (t.kind != SwiftDeclKind.enumType || t.isGeneric) return null;
    for (final m in t.members) {
      // `init(rawValue:)` (RawRepresentable) or a `rawValue` property.
      final r =
          m.kind == SwiftMemberKind.initializer &&
              m.title == 'init(rawValue:)' &&
              m.params.length == 1
          ? m.params.single.type
          : m.baseName == 'rawValue' && m.kind == SwiftMemberKind.property
          ? m.returnType
          : null;
      if (r is SwiftNamed &&
          !r.optional &&
          (r.usr == 's:Si' || r.usr == 's:SS')) {
        return r.usr;
      }
    }
    return null;
  }

  static int _cmp(String a, String b) {
    final x = a.split('.').map(int.parse).toList();
    final y = b.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
      if (c != 0) return c;
    }
    return 0;
  }

  /// Effective iOS version a member needs: its own, its type's and those of
  /// the module types in its signature.
  String? _needs(SwiftTypeDecl owner, SwiftMember? m) {
    final versions = <String>[
      ?owner.availability.introduced,
      if (m != null) ...[
        ?m.availability.introduced,
        for (final t in [m.returnType, for (final p in m.params) p.type])
          if (t is SwiftNamed) ?_byUsr[t.usr]?.availability.introduced,
      ],
    ];
    String? best;
    for (final v in versions) {
      if (best == null || _cmp(v, best) > 0) best = v;
    }
    return best != null && _cmp(best, minIos) > 0 ? best : null;
  }

  String _swiftAvailable(String? v, String indent) =>
      v == null ? '' : '$indent@available(iOS $v, *)\n';

  String _objcAvailable(String? v) =>
      v == null ? '' : ' API_AVAILABLE(ios($v))';

  String get _m => graph.name;

  /// Objective-C class name of the adapter of [t].
  String adapterName(SwiftTypeDecl t) => '${_m}_${t.name.replaceAll('.', '_')}';

  /// `NativeApiSwiftAdapters.podspec` for adapters of several modules:
  /// [dependencies] are pods providing non-SDK modules, [frameworks] SDK
  /// modules.
  static String podspec({
    required List<String> dependencies,
    required List<String> frameworks,
    String minIos = '15.0',
  }) {
    final b = StringBuffer()
      ..writeln('# GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln(
        '# @objc adapters for Swift-only APIs (native-api-bindgen). Add to ios/Podfile:',
      )
      ..writeln("#   pod 'NativeApiSwiftAdapters', :path => '<adapters dir>'")
      ..writeln('Pod::Spec.new do |s|')
      ..writeln("  s.name = 'NativeApiSwiftAdapters'")
      ..writeln(
        "  s.version = '${ProjectInfo.runtimeVersion.replaceAll(RegExp(r'-[a-z]+\.'), '.')}'",
      )
      ..writeln(
        "  s.summary = 'Generated @objc adapters for Swift-only APIs (local-only).'",
      )
      ..writeln(
        "  s.homepage = 'https://example.invalid/native-api-swift-adapters'",
      )
      ..writeln("  s.license = {:type => 'Apache-2.0'}")
      ..writeln("  s.authors = 'native-api-bindgen'")
      ..writeln("  s.platforms = {:ios => '$minIos'}")
      ..writeln("  s.source = {:path => '.'}")
      ..writeln("  s.source_files = '*.swift'")
      ..writeln("  s.swift_version = '5.0'");
    for (final d in dependencies) {
      b.writeln("  s.dependency '$d'");
    }
    if (frameworks.isNotEmpty) {
      b.writeln(
        '  s.frameworks = [${frameworks.map((f) => "'$f'").join(', ')}]',
      );
    }
    b.writeln('end');
    return b.toString();
  }

  /// Emits everything.
  SwiftAdapterOutput generate() {
    final selected = [
      for (final t in graph.types)
        if (types.isEmpty || types.contains(t.name)) t,
    ];
    _enums = {
      for (final t in selected)
        if (_rawType(t) != null &&
            !t.availability.unavailable &&
            !t.objcVisible)
          t.usr: _rawType(t)!,
    };
    final adapted = <String, SwiftTypeDecl>{};
    for (final t in selected) {
      if (_typeReason(t) == null && !_enums.containsKey(t.usr)) {
        adapted[t.usr] = t;
      }
    }

    final irTypes = <ApiType>[];
    final swift = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln(
        '// Generated by ${ProjectInfo.name} ${ProjectInfo.generatorVersion}: @objc adapters for the',
      )
      ..writeln(
        '// Objective-C-representable subset of the Swift module `$_m`.',
      )
      ..writeln('import Foundation');
    if (importModule) swift.writeln('import $_m');
    if (_enums.isNotEmpty) {
      swift
        ..writeln()
        ..writeln(
          '/// Converts a raw value received from Objective-C to an enum value.',
        )
        ..writeln(
          'fileprivate func _nabEnum<T: RawRepresentable>(_ type: T.Type, _ raw: T.RawValue) -> T {',
        )
        ..writeln('    guard let value = T(rawValue: raw) else {')
        ..writeln(
          '        preconditionFailure("native-api-bindgen: invalid raw value \\(raw) for \\(T.self)")',
        )
        ..writeln('    }')
        ..writeln('    return value')
        ..writeln('}');
    }
    final header = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln(
        '// Objective-C view of the @objc adapters for `$_m` (binding input; not compiled).',
      )
      ..writeln('#import <Foundation/Foundation.h>')
      ..writeln()
      ..writeln('NS_ASSUME_NONNULL_BEGIN')
      ..writeln();
    for (final t in adapted.values) {
      header.writeln('@class ${adapterName(t)};');
    }
    for (final u in _enums.keys) {
      header.writeln('@class ${adapterName(_byUsr[u]!)};');
    }
    if (adapted.isNotEmpty) header.writeln();

    for (final t in selected) {
      final reason = _typeReason(t);
      final members = <ApiMethod>[];
      final props = <ApiProperty>[];
      if (reason != null) {
        irTypes.add(_irType(t, const [], const [], reason));
        continue;
      }
      if (_enums.containsKey(t.usr)) {
        irTypes.add(_emitEnum(swift, header, t));
        continue;
      }
      final name = adapterName(t);
      final isStruct = t.kind == SwiftDeclKind.structType;
      final typeNeeds = _needs(t, null);
      swift
        ..writeln()
        ..writeln('/// Adapter for `$_m.${t.name}`.')
        ..write(_swiftAvailable(typeNeeds, ''))
        ..writeln('@objc($name)')
        ..writeln('public final class $name: NSObject {')
        ..writeln('    /// The adapted Swift ${isStruct ? 'value' : 'object'}.')
        ..writeln('    public ${isStruct ? 'var' : 'let'} wrapped: ${t.name}')
        ..writeln()
        ..writeln('    public init(wrapped: ${t.name}) {')
        ..writeln('        self.wrapped = wrapped')
        ..writeln('    }');
      header
        ..writeln('/// Adapter for the Swift type `$_m.${t.name}`.')
        ..writeln(
          '${typeNeeds == null ? '' : 'API_AVAILABLE(ios($typeNeeds))\n'}@interface $name : NSObject',
        );
      final usedSelectors = <String>{};
      for (final m in t.members) {
        final why = _memberReason(m, adapted);
        if (why != null) {
          members.add(_irMethod(t, m, why));
          continue;
        }
        switch (m.kind) {
          case SwiftMemberKind.property || SwiftMemberKind.typeProperty:
            _emitProperty(swift, header, t, m, adapted, usedSelectors);
            props.add(
              ApiProperty(
                name: m.baseName,
                type: _irTypeRef(m.returnType),
                getterId: _id(t, m),
                setterId: m.settable ? '${_id(t, m)}=' : null,
              ),
            );
            members.add(_irMethod(t, m, null));
          default:
            final sel = _selector(m);
            if (!usedSelectors.add(
              '${m.kind == SwiftMemberKind.typeMethod ? '+' : '-'}$sel',
            )) {
              members.add(
                _irMethod(t, m, (
                  DiagnosticCode.unsupportedType,
                  'Selector $sel collides with another member',
                )),
              );
              continue;
            }
            _emitMethod(swift, header, t, m, sel, adapted);
            members.add(_irMethod(t, m, null, selector: sel));
        }
      }
      swift.writeln('}');
      header
        ..writeln('@end')
        ..writeln();
      irTypes.add(_irType(t, members, props, null));
    }
    header.writeln('NS_ASSUME_NONNULL_END');

    return SwiftAdapterOutput._(
      swift.toString(),
      header.toString(),
      ApiModule(
        platform: ApiPlatform.apple,
        sdkVersion: sdkVersion,
        generatorVersion: ProjectInfo.generatorVersion,
        types: irTypes,
      ),
    );
  }

  // ------------------------------------------------------------- decisions

  (DiagnosticCode, String)? _typeReason(SwiftTypeDecl t) {
    if (t.availability.unavailable) {
      return (DiagnosticCode.availabilityMismatch, 'Unavailable on iOS');
    }
    if (t.objcVisible) {
      return (
        DiagnosticCode.outsideClosure,
        'Objective-C class: bound through the generated Objective-C header (Layer 1), no adapter needed',
      );
    }
    if (t.isGeneric) {
      return (
        DiagnosticCode.unsupportedGeneric,
        'Generic Swift types are not representable in Objective-C',
      );
    }
    return switch (t.kind) {
      SwiftDeclKind.classType || SwiftDeclKind.structType => null,
      SwiftDeclKind.enumType when _rawType(t) != null => null,
      SwiftDeclKind.enumType => (
        DiagnosticCode.unsupportedType,
        'Only Swift enums with an Int or String raw value are bridged (as the raw value)',
      ),
      SwiftDeclKind.protocolType => (
        DiagnosticCode.unsupportedCallback,
        'Swift protocols cannot be adapted (implementing them from Dart is planned)',
      ),
      SwiftDeclKind.other => (DiagnosticCode.unsupportedType, 'Not adapted'),
    };
  }

  /// Reason a type cannot cross the adapter, or null.
  (DiagnosticCode, String)? _typeUse(
    SwiftType t,
    Map<String, SwiftTypeDecl> adapted,
  ) {
    switch (t) {
      case SwiftVoid():
        return null;
      case SwiftOther(:final code, :final reason):
        return (code, reason);
      case SwiftArray(:final element):
        if (_elementOk(element, adapted)) return null;
        return (
          DiagnosticCode.unsupportedType,
          'Array element ${element.display} has no Objective-C bridge or adapter',
        );
      case SwiftDictionary(:final key, :final value):
        if (key.usr == 's:SS' && _elementOk(value, adapted)) return null;
        return (
          DiagnosticCode.unsupportedType,
          'Only String-keyed dictionaries with bridged or adapted values are bridged',
        );
      case SwiftNamed(:final usr, :final optional, :final display)
          when _enums.containsKey(usr):
        if (optional && _enums[usr] == 's:Si') {
          return (
            DiagnosticCode.unsupportedType,
            'Optional $display (Int raw value) is not representable in Objective-C',
          );
        }
        return null;
      case SwiftNamed(:final usr, :final optional, :final display):
        final b = _bridged[usr];
        if (b != null) {
          if (optional && !b.object) {
            return (
              DiagnosticCode.unsupportedType,
              'Optional $display is not representable in Objective-C',
            );
          }
          return null;
        }
        if (usr != null && adapted.containsKey(usr)) return null;
        return (
          DiagnosticCode.unsupportedType,
          'Type $display has no Objective-C bridge or adapter',
        );
    }
  }

  bool _elementOk(SwiftNamed e, Map<String, SwiftTypeDecl> adapted) =>
      !e.optional &&
      (_bridged.containsKey(e.usr) || adapted.containsKey(e.usr));

  /// Whether [t] bridges to an Objective-C object type that is never nil
  /// (what a throwing `@objc` method may return).
  bool _nonOptionalObject(SwiftType t, Map<String, SwiftTypeDecl> adapted) =>
      switch (t) {
        SwiftNamed(:final usr, :final optional) =>
          !optional &&
              (adapted.containsKey(usr) ||
                  (_bridged[usr]?.object ?? false) ||
                  _enums[usr] == 's:SS'),
        SwiftArray(:final optional) ||
        SwiftDictionary(:final optional) => !optional,
        _ => false,
      };

  (DiagnosticCode, String)? _memberReason(
    SwiftMember m,
    Map<String, SwiftTypeDecl> adapted,
  ) {
    if (m.availability.unavailable) {
      return (DiagnosticCode.availabilityMismatch, 'Unavailable on iOS');
    }
    if ((_nsObjectMembers.contains(m.baseName) &&
            m.kind != SwiftMemberKind.initializer) ||
        (m.kind == SwiftMemberKind.initializer && m.params.isEmpty)) {
      return (
        DiagnosticCode.unsupportedType,
        'Collides with an NSObject member of the adapter class',
      );
    }
    if (m.synthesized || m.kind == SwiftMemberKind.other) {
      return (
        DiagnosticCode.unsupportedType,
        'Operators and synthesized conformance members are not adapted',
      );
    }
    if (m.kind == SwiftMemberKind.enumCase) {
      return (
        DiagnosticCode.unsupportedType,
        'Enum cases of types without a raw-value bridge are not adapted',
      );
    }
    if (m.isAsync &&
        (m.kind == SwiftMemberKind.initializer ||
            m.kind == SwiftMemberKind.property ||
            m.kind == SwiftMemberKind.typeProperty ||
            m.isMutating)) {
      return (
        DiagnosticCode.unsupportedCallback,
        'async initializers, properties and mutating methods are not adapted',
      );
    }
    if (m.throws &&
        !m.isAsync &&
        (m.kind == SwiftMemberKind.property ||
            m.kind == SwiftMemberKind.typeProperty)) {
      return (
        DiagnosticCode.unsupportedType,
        'Throwing property accessors are not representable in Objective-C',
      );
    }
    if (m.throws &&
        !m.isAsync &&
        m.kind != SwiftMemberKind.initializer &&
        m.returnType is! SwiftVoid &&
        !_nonOptionalObject(m.returnType, adapted)) {
      return (
        DiagnosticCode.unsupportedType,
        'Throwing functions bridge to NSError ** only when they return Void or a non-optional object (${m.returnType.display})',
      );
    }
    if (m.isGeneric) {
      return (
        DiagnosticCode.unsupportedGeneric,
        'Generic functions are not representable in Objective-C',
      );
    }
    if (m.isFailable) {
      return (
        DiagnosticCode.unsupportedType,
        'Failable initializers are not adapted yet',
      );
    }
    for (final t in [m.returnType, for (final p in m.params) p.type]) {
      final r = _typeUse(t, adapted);
      if (r != null) return r;
    }
    return null;
  }

  // ------------------------------------------------------------- emission

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  /// Objective-C selector of a method/initializer: the first label is
  /// appended to the base name (`increment(by:)` -> `incrementBy:`,
  /// `init(start:label:)` -> `initWithStart:label:`); unlabeled parameters
  /// use their internal name after the first.
  String _selector(SwiftMember m) {
    final sel = _baseSelector(m);
    final base = m.kind == SwiftMemberKind.initializer ? 'init' : m.baseName;
    if (m.isAsync) {
      return m.params.isEmpty ? '${base}WithCompletion:' : '${sel}completion:';
    }
    if (m.throws) {
      return m.params.isEmpty ? '${base}AndReturnError:' : '${sel}error:';
    }
    return sel;
  }

  String _baseSelector(SwiftMember m) {
    final base = m.kind == SwiftMemberKind.initializer ? 'init' : m.baseName;
    if (m.params.isEmpty) return base;
    final parts = <String>[];
    for (var i = 0; i < m.params.length; i++) {
      final p = m.params[i];
      if (i == 0) {
        parts.add(
          p.label == '_'
              ? base
              : m.kind == SwiftMemberKind.initializer
              ? 'initWith${_cap(p.label)}'
              : '$base${_cap(p.label)}',
        );
      } else {
        parts.add(p.label == '_' ? p.name : p.label);
      }
    }
    return '${parts.join(':')}:';
  }

  /// Adapter-side Swift spelling of a nominal type (adapter class, raw
  /// value type of a bridged enum, or the type itself).
  String _swiftName(SwiftNamed t, Map<String, SwiftTypeDecl> adapted) {
    if (adapted.containsKey(t.usr)) return adapterName(adapted[t.usr]!);
    final raw = _enums[t.usr];
    if (raw != null) return raw == 's:Si' ? 'Int' : 'String';
    return t.name;
  }

  String _swiftType(SwiftType t, Map<String, SwiftTypeDecl> adapted) =>
      switch (t) {
        SwiftVoid() => 'Void',
        SwiftNamed(:final optional) =>
          _swiftName(t, adapted) + (optional ? '?' : ''),
        SwiftArray(:final element, :final optional) =>
          '[${_swiftName(element, adapted)}]${optional ? '?' : ''}',
        SwiftDictionary(:final value, :final optional) =>
          '[String: ${_swiftName(value, adapted)}]${optional ? '?' : ''}',
        SwiftOther(:final display) => display,
      };

  /// Objective-C object type of a collection element (`NSNumber` for
  /// scalars).
  String _objcElement(SwiftNamed e, Map<String, SwiftTypeDecl> adapted) {
    final b = _bridged[e.usr];
    if (b != null) return b.object ? '${b.objc} *' : 'NSNumber *';
    return '${adapterName(adapted[e.usr]!)} *';
  }

  String _objcType(SwiftType t, Map<String, SwiftTypeDecl> adapted) {
    switch (t) {
      case SwiftVoid():
        return 'void';
      case SwiftArray(:final element, :final optional):
        return 'NSArray<${_objcElement(element, adapted)}> *${optional ? ' _Nullable' : ''}';
      case SwiftDictionary(:final value, :final optional):
        return 'NSDictionary<NSString *, ${_objcElement(value, adapted)}> *${optional ? ' _Nullable' : ''}';
      case SwiftNamed(:final usr, :final optional) when _enums.containsKey(usr):
        return _enums[usr] == 's:Si'
            ? 'NSInteger'
            : 'NSString *${optional ? ' _Nullable' : ''}';
      case SwiftNamed(:final usr, :final optional):
        final b = _bridged[usr];
        final nullable = optional ? ' _Nullable' : '';
        if (b != null) return b.object ? '${b.objc} *$nullable' : b.objc;
        return '${adapterName(adapted[usr]!)} *$nullable';
      case SwiftOther():
        throw StateError('unsupported type reached emission');
    }
  }

  /// Converts an adapter-side value to the Swift value.
  String _unwrap(String expr, SwiftType t, Map<String, SwiftTypeDecl> adapted) {
    switch (t) {
      case SwiftNamed(:final usr, :final optional) when _enums.containsKey(usr):
        final name = _byUsr[usr]!.name;
        return optional
            ? '$expr.map { _nabEnum($name.self, \$0) }'
            : '_nabEnum($name.self, $expr)';
      case SwiftNamed(:final usr, :final optional)
          when adapted.containsKey(usr):
        return optional ? '$expr?.wrapped' : '$expr.wrapped';
      case SwiftArray(:final element, :final optional)
          when adapted.containsKey(element.usr):
        return '$expr${optional ? '?' : ''}.map { \$0.wrapped }';
      case SwiftDictionary(:final value, :final optional)
          when adapted.containsKey(value.usr):
        return '$expr${optional ? '?' : ''}.mapValues { \$0.wrapped }';
      default:
        return expr;
    }
  }

  /// Converts a Swift value to the adapter-side value.
  String _wrap(String expr, SwiftType t, Map<String, SwiftTypeDecl> adapted) {
    switch (t) {
      case SwiftNamed(:final usr, :final optional) when _enums.containsKey(usr):
        return optional ? '$expr?.rawValue' : '$expr.rawValue';
      case SwiftNamed(:final usr, :final optional)
          when adapted.containsKey(usr):
        final a = adapterName(adapted[usr]!);
        return optional
            ? '$expr.map { $a(wrapped: \$0) }'
            : '$a(wrapped: $expr)';
      case SwiftArray(:final element, :final optional)
          when adapted.containsKey(element.usr):
        final a = adapterName(adapted[element.usr]!);
        return '$expr${optional ? '?' : ''}.map { $a(wrapped: \$0) }';
      case SwiftDictionary(:final value, :final optional)
          when adapted.containsKey(value.usr):
        final a = adapterName(adapted[value.usr]!);
        return '$expr${optional ? '?' : ''}.mapValues { $a(wrapped: \$0) }';
      default:
        return expr;
    }
  }

  /// Bridged enum: an `NSObject` class whose class properties are the raw
  /// values of the cases.
  ApiType _emitEnum(StringBuffer swift, StringBuffer header, SwiftTypeDecl t) {
    final name = adapterName(t);
    final isInt = _enums[t.usr] == 's:Si';
    final needs = _needs(t, null);
    final members = <ApiMethod>[];
    final props = <ApiProperty>[];
    swift
      ..writeln()
      ..writeln(
        '/// Raw values of the cases of `$_m.${t.name}` (values cross as `${isInt ? 'Int' : 'String'}`).',
      )
      ..write(_swiftAvailable(needs, ''))
      ..writeln('@objc($name)')
      ..writeln('public final class $name: NSObject {');
    header
      ..writeln(
        '/// Raw values of the cases of the Swift enum `$_m.${t.name}`.',
      )
      ..writeln(
        '${needs == null ? '' : 'API_AVAILABLE(ios($needs))\n'}@interface $name : NSObject',
      );
    for (final m in t.members) {
      if (m.kind != SwiftMemberKind.enumCase) {
        members.add(
          _irMethod(t, m, (
            DiagnosticCode.unsupportedType,
            'Members of bridged enums are not adapted (values cross as raw values)',
          )),
        );
        continue;
      }
      if (_nsObjectMembers.contains(m.baseName) || m.availability.unavailable) {
        members.add(
          _irMethod(t, m, (
            DiagnosticCode.unsupportedType,
            'Case name collides with an NSObject member or is unavailable',
          )),
        );
        continue;
      }
      final caseNeeds = _needs(t, m);
      swift
        ..write(_swiftAvailable(caseNeeds, '    '))
        ..writeln(
          '    @objc public static var ${_ident(m.baseName)}: ${isInt ? 'Int' : 'String'} { ${t.name}.${_ident(m.baseName)}.rawValue }',
        );
      header.writeln(
        '@property (class, nonatomic, readonly) ${isInt ? 'NSInteger ' : 'NSString *'}${m.baseName}${_objcAvailable(caseNeeds)};',
      );
      props.add(
        ApiProperty(
          name: m.baseName,
          type: DeclaredTypeRef(isInt ? 'swift.Int' : 'swift.String'),
          getterId: _id(t, m),
        ),
      );
      members.add(_irMethod(t, m, null));
    }
    swift.writeln('}');
    header
      ..writeln('@end')
      ..writeln();
    return _irType(t, members, props, null);
  }

  /// Completion block of an async adapter: Swift and Objective-C spellings
  /// and the call that delivers a result ([value]) or an error.
  ({String swift, String objc, String ok, String fail}) _completion(
    SwiftMember m,
    Map<String, SwiftTypeDecl> adapted,
  ) {
    final r = m.returnType;
    final isVoid = r is SwiftVoid;
    if (!m.throws) {
      return isVoid
          ? (
              swift: '() -> Void',
              objc: 'void (^)(void)',
              ok: 'completion()',
              fail: '',
            )
          : (
              swift: '(${_swiftType(r, adapted)}) -> Void',
              objc: 'void (^)(${_objcType(r, adapted)})',
              ok: 'completion(VALUE)',
              fail: '',
            );
    }
    if (isVoid) {
      return (
        swift: '(Error?) -> Void',
        objc: 'void (^)(NSError * _Nullable)',
        ok: 'completion(nil)',
        fail: 'completion(error)',
      );
    }
    final objc = _objcType(r, adapted);
    final isObject = objc.contains('*');
    if (isObject) {
      final st = _swiftType(r, adapted);
      final optional = st.endsWith('?') ? st : '$st?';
      final nullable = objc.contains('_Nullable') ? objc : '$objc _Nullable';
      return (
        swift: '($optional, Error?) -> Void',
        objc: 'void (^)($nullable, NSError * _Nullable)',
        ok: 'completion(VALUE, nil)',
        fail: 'completion(nil, error)',
      );
    }
    final zero = objc == 'BOOL' ? 'false' : '0';
    return (
      swift: '(${_swiftType(r, adapted)}, Error?) -> Void',
      objc: 'void (^)($objc, NSError * _Nullable)',
      ok: 'completion(VALUE, nil)',
      fail: 'completion($zero, error)',
    );
  }

  void _emitMethod(
    StringBuffer swift,
    StringBuffer header,
    SwiftTypeDecl t,
    SwiftMember m,
    String sel,
    Map<String, SwiftTypeDecl> adapted,
  ) {
    final isInit = m.kind == SwiftMemberKind.initializer;
    final isStatic = m.kind == SwiftMemberKind.typeMethod;
    final completion = m.isAsync ? _completion(m, adapted) : null;
    final params = [
      for (final p in m.params)
        '${p.label == '_'
            ? '_ '
            : p.label == p.name
            ? ''
            : '${_label(p.label)} '}${_ident(p.name)}: ${_swiftType(p.type, adapted)}',
      if (completion != null) 'completion: @escaping ${completion.swift}',
    ].join(', ');
    final args = [
      for (final p in m.params)
        '${p.label == '_' ? '' : '${_label(p.label)}: '}${_unwrap(_ident(p.name), p.type, adapted)}',
    ].join(', ');
    final needs = _needs(t, m);
    final throws = m.throws && !m.isAsync;
    final tryKw = m.throws ? 'try ' : '';
    swift.writeln();
    swift.writeln('    /// `${m.declaration.replaceAll('`', "'")}`');
    swift.write(_swiftAvailable(needs, '    '));
    final objcParams = [
      for (final p in m.params)
        (type: _objcType(p.type, adapted), name: p.name),
    ];
    if (isInit) {
      swift
        ..writeln('    @objc($sel)')
        ..writeln('    public init($params)${throws ? ' throws' : ''} {')
        ..writeln('        self.wrapped = $tryKw${t.name}($args)')
        ..writeln('    }');
      header.writeln(
        '- (${throws ? 'nullable ' : ''}instancetype)${_headerParams(sel, objcParams, throws: throws)}${_objcAvailable(needs)};',
      );
      return;
    }
    final ret = m.returnType;
    final target = isStatic ? t.name : 'self.wrapped';
    final call = '$target.${_ident(m.baseName)}($args)';
    if (completion != null) {
      final value = ret is SwiftVoid ? '' : _wrap('value', ret, adapted);
      final ok = completion.ok.replaceAll('VALUE', value);
      swift
        ..writeln('    @objc($sel)')
        ..writeln(
          '    public ${isStatic ? 'static ' : ''}func ${_ident(m.baseName)}($params) {',
        )
        ..writeln('        Task {');
      if (m.throws) {
        swift
          ..writeln('            do {')
          ..writeln(
            ret is SwiftVoid
                ? '                try await $call'
                : '                let value = try await $call',
          )
          ..writeln('                $ok')
          ..writeln('            } catch {')
          ..writeln('                ${completion.fail}')
          ..writeln('            }');
      } else {
        swift
          ..writeln(
            ret is SwiftVoid
                ? '            await $call'
                : '            let value = await $call',
          )
          ..writeln('            $ok');
      }
      swift
        ..writeln('        }')
        ..writeln('    }');
      header.writeln(
        '${isStatic ? '+' : '-'} (void)${_headerParams(sel, [...objcParams, (type: completion.objc, name: 'completion')])}${_objcAvailable(needs)};',
      );
      return;
    }
    final retSwift = ret is SwiftVoid ? '' : ' -> ${_swiftType(ret, adapted)}';
    swift
      ..writeln('    @objc($sel)')
      ..writeln(
        '    public ${isStatic ? 'static ' : ''}func ${_ident(m.baseName)}($params)${throws ? ' throws' : ''}$retSwift {',
      )
      ..writeln(
        ret is SwiftVoid
            ? '        $tryKw$call'
            : '        return $tryKw${_wrap(call, ret, adapted)}',
      )
      ..writeln('    }');
    final objcRet = !throws
        ? _objcType(ret, adapted)
        : ret is SwiftVoid
        ? 'BOOL'
        : '${_objcType(ret, adapted).replaceAll(' _Nullable', '')} _Nullable';
    header.writeln(
      '${isStatic ? '+' : '-'} ($objcRet)${_headerParams(sel, objcParams, throws: throws)}${_objcAvailable(needs)};',
    );
  }

  /// Objective-C selector with parameter types: one piece per parameter,
  /// plus `(NSError **)error` for throwing members.
  String _headerParams(
    String sel,
    List<({String type, String name})> params, {
    bool throws = false,
  }) {
    final all = [...params, if (throws) (type: 'NSError **', name: 'error')];
    if (all.isEmpty) return sel;
    final pieces = sel.split(':')..removeLast();
    return [
      for (var i = 0; i < all.length; i++)
        '${pieces[i]}:(${all[i].type})${all[i].name}',
    ].join(' ');
  }

  void _emitProperty(
    StringBuffer swift,
    StringBuffer header,
    SwiftTypeDecl t,
    SwiftMember m,
    Map<String, SwiftTypeDecl> adapted,
    Set<String> usedSelectors,
  ) {
    final isStatic = m.kind == SwiftMemberKind.typeProperty;
    final type = m.returnType;
    final target = isStatic ? t.name : 'wrapped';
    final settable = m.settable && !isStatic;
    usedSelectors.add('${isStatic ? '+' : '-'}${m.baseName}');
    final needs = _needs(t, m);
    final name = _ident(m.baseName);
    swift
      ..writeln()
      ..writeln('    /// `${m.declaration.replaceAll('`', "'")}`')
      ..write(_swiftAvailable(needs, '    '))
      ..writeln(
        '    @objc public ${isStatic ? 'static ' : ''}var $name: ${_swiftType(type, adapted)} {',
      );
    if (settable) {
      swift
        ..writeln('        get { ${_wrap('$target.$name', type, adapted)} }')
        ..writeln(
          '        set { $target.$name = ${_unwrap('newValue', type, adapted)} }',
        );
    } else {
      swift.writeln('        ${_wrap('$target.$name', type, adapted)}');
    }
    swift.writeln('    }');
    final objc = _objcType(type, adapted);
    final attrs = [
      if (isStatic) 'class',
      'nonatomic',
      if (!settable) 'readonly',
      if (settable && objc.contains('*')) 'strong',
    ];
    header.writeln(
      '@property (${attrs.join(', ')}) $objc${objc.endsWith('*') || objc.endsWith('_Nullable') ? '' : ' '}${m.baseName}${_objcAvailable(needs)};',
    );
  }

  // ------------------------------------------------------------- IR

  String _typeId(SwiftTypeDecl t) => '$_m.${t.name}';

  String _id(SwiftTypeDecl t, SwiftMember m) => '${_typeId(t)}#${m.title}';

  TypeRef _irTypeRef(SwiftType t) => switch (t) {
    SwiftVoid() => const PrimitiveTypeRef(PrimitiveKind.void_),
    SwiftArray(:final optional) ||
    SwiftDictionary(:final optional) => DeclaredTypeRef(
      'swift.${t.display}',
      nullability: optional ? Nullability.nullable : Nullability.nonnull,
    ),
    SwiftNamed(:final name, :final optional) => DeclaredTypeRef(
      'swift.$name',
      nullability: optional ? Nullability.nullable : Nullability.nonnull,
    ),
    SwiftOther(:final display) => DeclaredTypeRef(
      'swift.unsupported<$display>',
    ),
  };

  ApiMethod _irMethod(
    SwiftTypeDecl t,
    SwiftMember m,
    (DiagnosticCode, String)? why, {
    String? selector,
  }) => ApiMethod(
    id: _id(t, m),
    name: m.title,
    kind: m.kind == SwiftMemberKind.initializer
        ? MethodKind.constructor
        : MethodKind.method,
    returnType: _irTypeRef(m.returnType),
    parameters: [
      for (final p in m.params) ApiParameter(p.name, _irTypeRef(p.type)),
    ],
    asyncKind: m.isAsync ? AsyncKind.future : AsyncKind.none,
    nativeDescriptor: selector,
    modifiers: {
      Modifier.public,
      if (m.kind == SwiftMemberKind.typeMethod ||
          m.kind == SwiftMemberKind.typeProperty)
        Modifier.static_,
    },
    support: why == null ? SupportStatus.supported : SupportStatus.unsupported,
    diagnostics: [
      if (why != null)
        Diagnostic(
          why.$1,
          why.$2,
          symbolId: _id(t, m),
          severity: Severity.warning,
        ),
    ],
  );

  ApiType _irType(
    SwiftTypeDecl t,
    List<ApiMethod> methods,
    List<ApiProperty> props,
    (DiagnosticCode, String)? why,
  ) => ApiType(
    id: _typeId(t),
    name: t.name,
    kind: switch (t.kind) {
      SwiftDeclKind.classType => TypeKind.classType,
      SwiftDeclKind.structType => TypeKind.struct,
      SwiftDeclKind.enumType => TypeKind.enumType,
      SwiftDeclKind.protocolType => TypeKind.protocol,
      SwiftDeclKind.other => TypeKind.classType,
    },
    namespace: _m,
    provenance: Provenance(
      platform: ApiPlatform.apple,
      sourceKind: 'swift-symbolgraph',
      sdkVersion: sdkVersion,
      localArtifact: '$_m.symbols.json',
    ),
    methods: SplayTreeMap<String, ApiMethod>.fromIterable(
      methods,
      key: (m) => (m as ApiMethod).id,
    ).values.toList(),
    properties: props,
    modifiers: const {Modifier.public},
    support: why == null ? SupportStatus.supported : SupportStatus.unsupported,
    diagnostics: [
      if (why != null)
        Diagnostic(
          why.$1,
          why.$2,
          symbolId: _typeId(t),
          severity: why.$1 == DiagnosticCode.outsideClosure
              ? Severity.info
              : Severity.warning,
        ),
    ],
  );
}
