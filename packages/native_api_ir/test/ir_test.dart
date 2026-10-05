import 'dart:convert';

import 'package:native_api_ir/native_api_ir.dart';
import 'package:test/test.dart';

const _uri = DeclaredTypeRef(
  'android.net.Uri',
  nullability: Nullability.nullable,
);

ApiModule _sample() {
  const intent = 'android.content.Intent';
  return ApiModule(
    platform: ApiPlatform.android,
    sdkVersion: '36',
    generatorVersion: '0.1.0-dev.1',
    sourceRevision: '2',
    types: [
      ApiType(
        id: intent,
        name: 'Intent',
        kind: TypeKind.classType,
        namespace: 'android.content',
        provenance: const Provenance(
          platform: ApiPlatform.android,
          sourceKind: 'sdk',
          sdkVersion: '36',
          localArtifact: 'android.jar',
          artifactEntry: 'android/content/Intent.class',
        ),
        modifiers: {Modifier.public},
        superClass: const DeclaredTypeRef('java.lang.Object'),
        availability: const Availability(introduced: ApiVersion(1)),
        methods: [
          ApiMethod(
            id: SymbolIds.method(intent, 'setData', [_uri]),
            name: 'setData',
            kind: MethodKind.method,
            returnType: const DeclaredTypeRef(
              intent,
              nullability: Nullability.nonnull,
            ),
            parameters: const [
              ApiParameter('data', _uri, nameSource: 'LocalVariableTable'),
            ],
            modifiers: {Modifier.public},
            nativeDescriptor: '(Landroid/net/Uri;)Landroid/content/Intent;',
            availability: const Availability(introduced: ApiVersion(1)),
          ),
          ApiMethod(
            id: SymbolIds.method(intent, SymbolIds.constructorName, const []),
            name: SymbolIds.constructorName,
            kind: MethodKind.constructor,
            returnType: const PrimitiveTypeRef(PrimitiveKind.void_),
            modifiers: {Modifier.public},
          ),
        ],
        fields: [
          ApiField(
            id: SymbolIds.field(intent, 'ACTION_VIEW'),
            name: 'ACTION_VIEW',
            type: const DeclaredTypeRef('java.lang.String'),
            constantValue: const ConstantValue(
              'string',
              'android.intent.action.VIEW',
            ),
            modifiers: {Modifier.public, Modifier.static_, Modifier.final_},
          ),
        ],
      ),
    ],
  );
}

void main() {
  group('SymbolIds', () {
    test('method IDs use erased binary names', () {
      expect(
        SymbolIds.method('android.content.Intent', 'setData', [_uri]),
        'android.content.Intent#setData(android.net.Uri)',
      );
      expect(
        SymbolIds.method(
          'a.B',
          'm',
          const [
            ArrayTypeRef(PrimitiveTypeRef(PrimitiveKind.int_)),
            DeclaredTypeRef(
              'java.util.List',
              typeArguments: [WildcardTypeRef(TypeVariableRef('E'))],
            ),
            TypeVariableRef('T'),
          ],
          typeVariableErasures: {'T': 'java.lang.CharSequence'},
        ),
        'a.B#m(int[],java.util.List,java.lang.CharSequence)',
      );
      expect(SymbolIds.field('a.B', 'X'), 'a.B#X');
      expect(SymbolIds.ownerOf('a.B\$C#m()'), 'a.B\$C');
      expect(SymbolIds.isMember('a.B'), isFalse);
    });
  });

  group('JSON', () {
    test('round-trips and is canonical', () {
      final module = _sample();
      final text = module.toCanonicalJson();
      final decoded = ApiModule.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      expect(decoded.toCanonicalJson(), text);
      expect(text, contains('"schemaVersion": $irSchemaVersion'));
      expect(
        text.indexOf('"generatorVersion"'),
        lessThan(text.indexOf('"platform"')),
      );
    });

    test('type refs round-trip', () {
      const refs = <TypeRef>[
        PrimitiveTypeRef(PrimitiveKind.long),
        DeclaredTypeRef(
          'java.util.Map',
          typeArguments: [
            WildcardTypeRef(DeclaredTypeRef('java.lang.Number'), isSuper: true),
            WildcardTypeRef(null),
          ],
          nullability: Nullability.nonnull,
        ),
        ArrayTypeRef(TypeVariableRef('T', nullability: Nullability.nullable)),
      ];
      for (final r in refs) {
        expect(TypeRef.fromJson(r.toJson()), r);
      }
    });

    test('nodeById finds members', () {
      final m = _sample();
      expect(
        m.nodeById('android.content.Intent#setData(android.net.Uri)'),
        isA<ApiMethod>(),
      );
      expect(m.nodeById('android.content.Intent#ACTION_VIEW'), isA<ApiField>());
      expect(m.nodeById('android.content.Intent#nope()'), isNull);
    });

    test('constant values keep exact literals', () {
      const c = ConstantValue('long', '9223372036854775807');
      expect(ConstantValue.fromJson(c.toJson()), c);
    });
  });

  group('validation', () {
    test('valid module has no errors', () {
      expect(validateModule(_sample()), isEmpty);
    });

    test('detects duplicates, unexplained unsupported, hidden-supported', () {
      final base = _sample().types.single;
      final bad = base.copyWith(
        methods: [
          ...base.methods,
          base.methods.first,
          const ApiMethod(
            id: 'android.content.Intent#hidden()',
            name: 'hidden',
            kind: MethodKind.method,
            returnType: PrimitiveTypeRef(PrimitiveKind.void_),
            visibility: ApiVisibility.hiddenOrNonSdk,
          ),
          const ApiMethod(
            id: 'android.content.Intent#gone()',
            name: 'gone',
            kind: MethodKind.method,
            returnType: PrimitiveTypeRef(PrimitiveKind.void_),
            support: SupportStatus.unsupported,
          ),
          const ApiMethod(
            id: 'other.Type#x()',
            name: 'x',
            kind: MethodKind.method,
            returnType: PrimitiveTypeRef(PrimitiveKind.void_),
          ),
        ],
      );
      final m = ApiModule(
        platform: ApiPlatform.android,
        sdkVersion: '36',
        generatorVersion: 'x',
        types: [bad],
      );
      final messages = validateModule(m).map((d) => d.message).toList();
      expect(messages, contains('Duplicate symbol ID'));
      expect(
        messages,
        contains('Non-public symbol must not be marked supported'),
      );
      expect(messages, contains('Unsupported symbol has no reason diagnostic'));
      expect(
        messages.any((s) => s.startsWith('Member ID is not prefixed')),
        isTrue,
      );
    });
  });

  group('versions', () {
    test('parse, compare, print', () {
      expect(ApiVersion.parse('36.1') > ApiVersion.parse('36'), isTrue);
      expect(ApiVersion.parse('37.0'), const ApiVersion(37));
      expect('${ApiVersion.parse('36.1')}', '36.1');
      expect(() => ApiVersion.parse('x'), throwsFormatException);
      const a = Availability(introduced: ApiVersion(36, 1));
      expect(a.isAvailableAt(const ApiVersion(36)), isFalse);
      expect(a.isAvailableAt(const ApiVersion(36, 1)), isTrue);
      expect(Availability.fromJson(a.toJson()), a);
    });
  });

  group('schema v2 (Apple)', () {
    test(
      'pointer, block, unsigned and per-platform availability round-trip',
      () {
        const refs = <TypeRef>[
          PrimitiveTypeRef(PrimitiveKind.uint64),
          PointerTypeRef(PointerTypeRef(DeclaredTypeRef('Foundation.NSError'))),
          BlockTypeRef(
            PrimitiveTypeRef(PrimitiveKind.void_),
            [
              PrimitiveTypeRef(PrimitiveKind.boolean),
              DeclaredTypeRef(
                'Foundation.NSError',
                nullability: Nullability.nullable,
              ),
            ],
            nullability: Nullability.nonnull,
          ),
        ];
        for (final r in refs) {
          expect(TypeRef.fromJson(r.toJson()), r);
        }
        const a = Availability(
          platforms: {
            'ios': PlatformAvailability(
              introduced: ApiVersion(15, 0),
              deprecated: ApiVersion(17, 0, 1),
            ),
            'macos': PlatformAvailability(unavailable: true),
          },
        );
        expect(Availability.fromJson(a.toJson()), a);
        expect('${ApiVersion.parse('17.0.1')}', '17.0.1');
        expect(ApiVersion.parse('17.0.1') > ApiVersion.parse('17'), isTrue);
      },
    );

    test('v1 documents still decode', () {
      final v1 = {
        'schemaVersion': 1,
        'platform': 'android',
        'sdkVersion': '36',
        'generatorVersion': 'x',
        'types': <Object?>[],
      };
      expect(ApiModule.fromJson(v1).types, isEmpty);
      expect(
        () => ApiModule.fromJson({...v1, 'schemaVersion': 99}),
        throwsFormatException,
      );
    });
  });

  group('diagnostics', () {
    test('codes are unique and stable', () {
      final codes = DiagnosticCode.values.map((c) => c.code).toSet();
      expect(codes.length, DiagnosticCode.values.length);
      expect(DiagnosticCode.nonSdkApi.code, 'E006');
      expect(DiagnosticCode.tryParse('NON_SDK_API'), DiagnosticCode.nonSdkApi);
      const d = Diagnostic(
        DiagnosticCode.unsupportedGeneric,
        'erased',
        symbolId: 'a.B',
      );
      expect(Diagnostic.fromJson(d.toJson()), d);
    });
  });
}
