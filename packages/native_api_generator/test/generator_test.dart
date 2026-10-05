import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

ApiMethod _m(
  String name,
  List<TypeRef> params, {
  ApiVersion? since,
  bool ctor = false,
}) => ApiMethod(
  id: SymbolIds.method('a.B', ctor ? SymbolIds.constructorName : name, params),
  name: ctor ? SymbolIds.constructorName : name,
  kind: ctor ? MethodKind.constructor : MethodKind.method,
  returnType: const PrimitiveTypeRef(PrimitiveKind.void_),
  parameters: [
    for (var i = 0; i < params.length; i++) ApiParameter('p$i', params[i]),
  ],
  availability: Availability(introduced: since ?? const ApiVersion(1)),
);

class _Resolver implements DartTypeResolver {
  @override
  String? qualifiedName(String typeId) =>
      typeId == 'android.net.Uri' ? 'android_net.Uri' : null;

  @override
  int typeParameterCount(String typeId) => 0;
}

void main() {
  group('identifiers', () {
    test('reserved words escaped; built-ins allowed as members', () {
      expect(Identifiers.dartMember('switch'), r'switch$');
      expect(Identifiers.dartMember('get'), 'get');
      expect(Identifiers.dartMember('toString'), r'toString$');
      expect(Identifiers.dartMember('release'), r'release$');
      expect(Identifiers.dartMember('type'), r'type$');
      expect(Identifiers.dartMember('_hidden'), r'$_hidden');
      expect(Identifiers.dartType('Object'), r'Object$');
      expect(Identifiers.dartType(r'Handler$Callback'), 'Handler_Callback');
      expect(Identifiers.dartType('Function'), r'Function$');
      expect(Identifiers.typescript('function'), 'function_');
      expect(Identifiers.packagePrefix('android.content'), 'android_content');
    });
  });

  group('overloads', () {
    const s = DeclaredTypeRef('java.lang.String');
    const i = PrimitiveTypeRef(PrimitiveKind.int_);
    const l = PrimitiveTypeRef(PrimitiveKind.long);
    test('primary keeps plain name; others get signature suffixes', () {
      final names = OverloadNamer.assign([
        _m('put', [s, l]),
        _m('put', [s, i]),
        _m('put', [s, const ArrayTypeRef(i)]),
        _m('put', [s, s], since: const ApiVersion(12)),
        _m('only', [i]),
      ]);
      expect(names['a.B#put(java.lang.String,int)'], 'put');
      expect(names['a.B#put(java.lang.String,long)'], r'put$String$long');
      expect(names['a.B#put(java.lang.String,int[])'], r'put$String$intArray');
      expect(
        names['a.B#put(java.lang.String,java.lang.String)'],
        r'put$String$String',
      );
      expect(names['a.B#only(int)'], 'only');
    });

    test(
      'earliest introduced overload stays primary when newer ones appear',
      () {
        final names = OverloadNamer.assign([
          _m('m', [l], since: const ApiVersion(1)),
          _m('m', [i], since: const ApiVersion(30)),
        ]);
        expect(names['a.B#m(long)'], 'm');
        expect(names['a.B#m(int)'], r'm$int');
      },
    );

    test('constructors: primary unnamed, colliding suffixes disambiguated', () {
      final names = OverloadNamer.assign([
        _m('', const [], ctor: true),
        _m('', [const DeclaredTypeRef('x.Thing')], ctor: true),
        _m('', [const DeclaredTypeRef(r'y.Outer$Thing')], ctor: true),
      ]);
      expect(names['a.B#<init>()'], '');
      expect(names.values.toSet(), hasLength(3));
      expect(names['a.B#<init>(x.Thing)'], r'new$Thing');
      expect(names[r'a.B#<init>(y.Outer$Thing)'], r'new$y_Outer_Thing');
    });
  });

  group('type mapping', () {
    final mapper = DartJniTypeMapper(_Resolver());
    test('primitives carry exact JNI widths', () {
      final i = mapper.map(const PrimitiveTypeRef(PrimitiveKind.int_));
      expect(
        (i.dartType, i.jniType, i.argWrapper),
        ('int', r'jni$.jint.type', r'jni$.JValueInt'),
      );
      expect(
        mapper.map(const PrimitiveTypeRef(PrimitiveKind.long)).argWrapper,
        isNull,
      );
      expect(
        mapper.map(const PrimitiveTypeRef(PrimitiveKind.float)).argWrapper,
        r'jni$.JValueFloat',
      );
      expect(
        mapper.map(const PrimitiveTypeRef(PrimitiveKind.char)).dartType,
        'int',
      );
    });

    test('references: generated, String, opaque, arrays, type variables', () {
      expect(
        mapper.map(const DeclaredTypeRef('android.net.Uri')).dartType,
        'android_net.Uri',
      );
      expect(
        mapper.map(const DeclaredTypeRef('java.lang.String')).dartType,
        r'jni$.JString',
      );
      final opaque = mapper.map(const DeclaredTypeRef('x.Unknown'));
      expect((opaque.dartType, opaque.isOpaque), (r'jni$.JObject', true));
      expect(
        mapper
            .map(const ArrayTypeRef(PrimitiveTypeRef(PrimitiveKind.byte)))
            .dartType,
        r'jni$.JByteArray',
      );
      expect(
        mapper
            .map(const ArrayTypeRef(DeclaredTypeRef('android.net.Uri')))
            .dartType,
        r'jni$.JArray<android_net.Uri?>',
      );
      expect(
        mapper
            .map(
              const TypeVariableRef('T'),
              typeVariableBounds: {
                'T': const DeclaredTypeRef('android.net.Uri'),
              },
            )
            .dartType,
        'android_net.Uri',
      );
      expect(
        mapper.dartTypeWithNullability(const DeclaredTypeRef('x.Y'), opaque),
        r'jni$.JObject?',
      );
    });

    test('ergonomic mode maps String to Dart String', () {
      final m = DartJniTypeMapper(
        _Resolver(),
        mode: GenerationMode.ergonomicDart,
      ).map(const DeclaredTypeRef('java.lang.String'));
      expect((m.dartType, m.ergonomicString), ('String', true));
    });
  });

  group('output', () {
    test('string literals escape quotes, dollars, backslashes, controls', () {
      expect(dartStringLiteral(r"it's $x \ y"), r"'it\'s \$x \\ y'");
      expect(dartStringLiteral('a\nb\u0001'), r"'a\nb\u{1}'");
      expect(dartStringLiteral('café'), "'café'");
    });

    test('writer removes only stale generated files', () {
      final tmp = Directory.systemTemp.createTempSync('out');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final guard = OutputGuard(tmp.path);
      final module = ApiModule(
        platform: ApiPlatform.android,
        sdkVersion: '36',
        generatorVersion: 'x',
        types: const [],
      );
      final header = generatedHeader(module);
      writeGeneration(
        guard,
        GenerationOutput(
          files: [
            GeneratedFile('a.dart', '${header}a'),
            GeneratedFile('b.dart', '${header}b'),
          ],
          bindings: const [],
          module: module,
          diagnostics: const [],
        ),
      );
      File(p.join(tmp.path, 'user.dart')).writeAsStringSync('mine');
      writeGeneration(
        guard,
        GenerationOutput(
          files: [GeneratedFile('a.dart', '${header}a2')],
          bindings: const [],
          module: module,
          diagnostics: const [],
        ),
      );
      expect(
        File(p.join(tmp.path, 'a.dart')).readAsStringSync(),
        endsWith('a2'),
      );
      expect(File(p.join(tmp.path, 'b.dart')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'user.dart')).existsSync(), isTrue);
      expect(header, isNot(contains(RegExp(r'\d{4}-\d{2}-\d{2}'))));
      expect(header, contains('Source SDK: Android API 36'));
    });
  });
}
