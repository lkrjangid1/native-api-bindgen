import 'dart:convert';
import 'dart:io';

import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:test/test.dart';

void main() {
  final module = ApiModule.fromJson(
    jsonDecode(
          File('../../tests/golden/ir/fixtures_basic.json').readAsStringSync(),
        )
        as Map<String, Object?>,
  );
  final sets = ConstantSets.of(module);
  const owner = 'com.example.fixtures.TypedConstants';

  test('sets are named from the shared constant prefix', () {
    expect(
      [for (final s in sets.declaredBy(owner)) '${s.name}:${s.kind}:${s.flag}'],
      [
        'Color:string:false',
        'Mode:int:false',
        'Size:long:false',
        'Style:int:true',
      ],
    );
  });

  test('members keep the SDK constants and values', () {
    final mode = sets.declaredBy(owner).firstWhere((s) => s.name == 'Mode');
    expect(
      [for (final f in mode.members) '${f.name}=${f.constantValue!.literal}'],
      ['MODE_AUTO=2', 'MODE_OFF=0', 'MODE_ON=1'],
    );
  });

  test('use sites resolve to their set', () {
    expect(sets.forReturn('$owner#getMode()')?.name, 'Mode');
    expect(sets.forParameter('$owner#setStyle(int)', 0)?.name, 'Style');
    expect(sets.forParameter('$owner#isBold(int)', 0)?.flag, isTrue);
    expect(sets.forReturn('$owner#getColor()')?.kind, 'string');
    expect(sets.forParameter('$owner#setMode(int)', 1), isNull);
    expect(sets.unresolved, 0);
  });
}
