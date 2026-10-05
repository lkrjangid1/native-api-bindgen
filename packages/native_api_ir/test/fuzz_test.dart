import 'dart:convert';
import 'dart:math';

import 'package:native_api_ir/native_api_ir.dart';
import 'package:test/test.dart';

void main() {
  test('malformed IR JSON never throws', () {
    final valid = jsonEncode({
      'schemaVersion': irSchemaVersion,
      'platform': 'android',
      'sdkVersion': '36',
      'generatorVersion': 'x',
      'types': [
        {
          'id': 'a.B',
          'name': 'B',
          'kind': 'classType',
          'namespace': 'a',
          'visibility': 'public',
          'support': 'supported',
          'provenance': {
            'platform': 'android',
            'sourceKind': 'sdk',
            'sdkVersion': '36',
          },
          'methods': [
            {
              'id': 'a.B#m()',
              'name': 'm',
              'kind': 'method',
              'visibility': 'public',
              'support': 'supported',
              'returnType': {'kind': 'primitive', 'name': 'int'},
            },
          ],
        },
      ],
    });
    expect(decodeModule(valid).module, isNotNull);

    final rnd = Random(42);
    for (var i = 0; i < 2000; i++) {
      final chars = valid.split('');
      final edits = 1 + rnd.nextInt(4);
      for (var e = 0; e < edits; e++) {
        final pos = rnd.nextInt(chars.length);
        switch (rnd.nextInt(3)) {
          case 0:
            chars.removeAt(pos);
          case 1:
            chars.insert(pos, String.fromCharCode(32 + rnd.nextInt(90)));
          default:
            chars[pos] = String.fromCharCode(32 + rnd.nextInt(90));
        }
      }
      final r = decodeModule(chars.join());
      expect(r.module != null || r.diagnostics.isNotEmpty, isTrue);
    }
  });

  test('deep nesting is rejected with a diagnostic', () {
    var t = '{"kind":"primitive","name":"int"}';
    for (var i = 0; i < 200; i++) {
      t = '{"kind":"array","component":$t}';
    }
    final text =
        '{"schemaVersion":$irSchemaVersion,"platform":"android","sdkVersion":"1",'
        '"generatorVersion":"x","types":[{"id":"a.B","name":"B","kind":"classType",'
        '"namespace":"a","visibility":"public","support":"supported",'
        '"provenance":{"platform":"android","sourceKind":"sdk","sdkVersion":"1"},'
        '"fields":[{"id":"a.B#f","name":"f","visibility":"public",'
        '"support":"supported","type":$t}]}]}';
    final r = decodeModule(text);
    expect(r.module, isNull);
    expect(r.diagnostics.single.code, DiagnosticCode.invalidAst);
  });
}
