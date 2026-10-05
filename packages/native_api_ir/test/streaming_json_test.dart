import 'package:native_api_ir/native_api_ir.dart';
import 'package:test/test.dart';

void main() {
  ApiModule module(int types) => ApiModule(
    platform: ApiPlatform.android,
    sdkVersion: '36',
    generatorVersion: '0.1.0',
    types: [
      for (var i = 0; i < types; i++)
        ApiType(
          id: 'p.T$i',
          name: 'T$i',
          kind: TypeKind.classType,
          namespace: 'p',
          provenance: const Provenance(
            platform: ApiPlatform.android,
            sourceKind: 'fixture',
            sdkVersion: '36',
          ),
          methods: [
            ApiMethod(
              id: 'p.T$i#m()',
              name: 'm',
              kind: MethodKind.method,
              returnType: const PrimitiveTypeRef(PrimitiveKind.int_),
            ),
          ],
        ),
    ],
    diagnostics: const [
      Diagnostic(DiagnosticCode.sdkNotFound, 'x', severity: Severity.info),
    ],
  );

  for (final n in [0, 1, 3]) {
    test('streamed canonical JSON is identical ($n types)', () {
      final m = module(n);
      final b = StringBuffer();
      m.writeCanonicalJson(b);
      expect(b.toString(), m.toCanonicalJson());
    });
  }

  test('writeCanonicalJsonWithList matches canonicalJson', () {
    final b = StringBuffer();
    writeCanonicalJsonWithList(
      b,
      {
        'a': 1,
        'b': {
          'z': 1,
          'y': [1, 2],
        },
      },
      'list',
      [
        {
          'k': 'v',
          'a': [1],
        },
        [],
        'x',
      ],
    );
    expect(
      b.toString(),
      canonicalJson({
        'a': 1,
        'b': {
          'z': 1,
          'y': [1, 2],
        },
        'list': [
          {
            'k': 'v',
            'a': [1],
          },
          [],
          'x',
        ],
      }),
    );
  });
}
