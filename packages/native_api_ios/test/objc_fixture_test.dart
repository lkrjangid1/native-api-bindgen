@TestOn('mac-os')
library;

import 'dart:io';

import 'package:native_api_ios/testing.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final sdk = testSdk;
  if (sdk == null) {
    test('objc fixtures', () {}, skip: 'Xcode/libclang not available');
    return;
  }
  late ApiModule module;
  setUpAll(() => module = extractObjCFixtures(sdk));

  ApiType type(String name) => module.typeById('NABFixtures.$name')!;
  ApiMethod method(String sel) =>
      module.nodeById('NABFixtures.NABThing#$sel')! as ApiMethod;
  List<String> codes(ApiNode n) => [for (final d in n.diagnostics) d.code.code];

  test('IR is valid and matches the committed snapshot', () {
    expect(
      validateModule(module).where((d) => d.severity == Severity.error),
      isEmpty,
    );
    final golden = File(
      p.join(
        findRepoRoot(),
        'tests',
        'golden',
        'ir',
        'objc_fixtures_basic.json',
      ),
    );
    final text = fixtureOnly(module).toCanonicalJson();
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      golden
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    expect(
      text,
      golden.readAsStringSync(),
      reason: 'run with UPDATE_GOLDENS=1 to accept changes',
    );
  });

  test('extraction is deterministic', () {
    expect(
      extractObjCFixtures(sdk).toCanonicalJson(),
      module.toCanonicalJson(),
    );
  });

  test('ancestors and protocols from the SDK join the closure', () {
    expect(module.typeById('ObjectiveC.NSObject'), isNotNull);
    expect(module.typeById('Foundation.NSCopying')!.kind, TypeKind.protocol);
    expect(type('NABListener').kind, TypeKind.protocol);
  });

  test('enums keep exact values including 64-bit unsigned', () {
    String v(String t, String f) =>
        type(t).fields.firstWhere((x) => x.name == f).constantValue!.literal;
    expect(v('NABMode', 'NABModeAuto'), '2');
    expect(v('NABFlags', 'NABFlagsB'), '2');
    expect(v('NABFlags', 'NABFlagsHigh'), '9223372036854775808');
  });

  test('structs with nested value fields', () {
    final rect = type('NABRect');
    expect(rect.kind, TypeKind.struct);
    expect(rect.fields.map((f) => (f.type as DeclaredTypeRef).name).toSet(), {
      'NABFixtures.NABPoint',
    });
  });

  test('nullability, generics and properties', () {
    expect(method('-name').returnType.nullability, Nullability.nullable);
    final items = method('-items').returnType as DeclaredTypeRef;
    expect(items.name, 'Foundation.NSArray');
    expect(items.nullability, Nullability.nonnull);
    expect(
      (items.typeArguments.single as DeclaredTypeRef).name,
      'Foundation.NSString',
    );
    final props = {for (final x in type('NABThing').properties) x.name: x};
    expect(props['count']!.setterId, isNull, reason: 'readonly');
    expect(props['name']!.setterId, 'NABFixtures.NABThing#-setName:');
    expect(props['instances']!.getterId, 'NABFixtures.NABThing#+instances');
  });

  test('categories merge into the class', () {
    expect(method('-describe').isGeneratable, isTrue);
  });

  test('availability per platform', () {
    final legacy = method('-legacy').availability;
    expect(legacy.platforms['ios']!.introduced.toString(), '13');
    expect(legacy.platforms['ios']!.deprecated.toString(), '15');
    final auto = type(
      'NABMode',
    ).fields.firstWhere((f) => f.name == 'NABModeAuto');
    expect(auto.availability.platforms['ios']!.introduced.toString(), '15');
    final mac = type('NABMacOnly');
    expect(mac.isGeneratable, isFalse);
    expect(codes(mac), contains('E012'));
  });

  test('private, variadic are skipped with reasons', () {
    expect(method('-_privateHelper').isGeneratable, isFalse);
    expect(codes(method('-_privateHelper')), contains('E005'));
    expect(method('-log:').isGeneratable, isFalse);
    expect(codes(method('-log:')), contains('E002'));
  });

  test('blocks and out-parameters are typed', () {
    expect(
      method('-runWithCompletion:').parameters.single.type,
      isA<BlockTypeRef>(),
    );
    expect(
      method('-saveToPath:error:').parameters.last.type,
      isA<PointerTypeRef>(),
    );
  });

  test('no absolute SDK path leaks into the IR', () {
    expect(module.toCanonicalJson(), isNot(contains(sdk.path)));
    expect(module.toCanonicalJson(), isNot(contains('/Applications/')));
  });
}
