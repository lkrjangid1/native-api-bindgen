@TestOn('mac-os')
library;

import 'dart:io';

import 'package:native_api_ios/native_api_ios.dart';
import 'package:native_api_ios/testing.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Swift Layer 2: symbol graph of fixtures/swift/basic (built with the
/// Xcode toolchain) -> @objc adapters. Goldens in tests/golden/swift.
void main() {
  final sdk = testSdk;
  if (sdk == null) {
    test('swift', () {}, skip: 'Xcode not available');
    return;
  }
  late Directory tmp;
  late SwiftModuleGraph graph;
  late SwiftAdapterOutput out;
  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('nab_swift_test');
    final root = findRepoRoot();
    final tc = SwiftToolchain(sdk);
    final mod = tc.emitModule('NABSwiftFixtures', [
      p.join(root, 'fixtures', 'swift', 'basic', 'NABSwiftFixtures.swift'),
    ], p.join(tmp.path, 'mod'));
    graph = SwiftModuleGraph.read(
      tc.extractSymbolGraph(
        'NABSwiftFixtures',
        p.join(tmp.path, 'sg'),
        includeDirs: [p.dirname(mod)],
      ),
    );
    out = SwiftAdapterGenerator(graph).generate();
  });
  tearDownAll(() => tmp.deleteSync(recursive: true));

  ApiMethod member(String type, String title) => out.module
      .typeById('NABSwiftFixtures.$type')!
      .methods
      .firstWhere((m) => m.name == title);

  test('symbol graph: types, members, parameters', () {
    expect(graph.types.map((t) => t.name), [
      'Counter',
      'CounterError',
      'Level',
      'Mood',
      'Temperature',
    ]);
    final inc = graph.types.first.members.firstWhere(
      (m) => m.title == 'increment(by:)',
    );
    expect(inc.params.single.label, 'by');
    expect(inc.params.single.name, 'step');
    expect((inc.params.single.type as SwiftNamed).usr, 's:Si');
  });

  test('adapted: methods, initializers, properties, statics', () {
    for (final (t, m) in [
      ('Counter', 'increment(by:)'),
      ('Counter', 'init(start:label:)'),
      ('Counter', 'describe(prefix:)'),
      ('Counter', 'make()'),
      ('Counter', 'label'),
      ('Temperature', 'reset()'),
      ('Temperature', 'adding(_:)'),
    ]) {
      expect(member(t, m).isGeneratable, isTrue, reason: '$t.$m');
    }
    expect(
      member('Counter', 'increment(by:)').nativeDescriptor,
      'incrementBy:',
    );
  });

  test('not adapted, with reasons', () {
    String? code(String m) => member('Counter', m).diagnostics.single.code.code;
    expect(code('transform(_:)'), 'E004'); // closure
    expect(code('identity(_:)'), 'E003'); // generic
    expect(code('pair()'), 'E002'); // tuple
    expect(code('count()'), 'E002'); // throws, returns Int
    expect(
      out.module.typeById('NABSwiftFixtures.CounterError')!.isGeneratable,
      isFalse,
    ); // enum without raw value
  });

  test('collections, throws, async and raw-value enums', () {
    for (final (m, sel) in [
      ('values()', 'values'),
      ('tags()', 'tags'),
      ('neighbors()', 'neighbors'),
      ('names(_:)', 'names:'),
      ('check(limit:)', 'checkLimit:error:'),
      ('duplicate(named:)', 'duplicateNamed:error:'),
      ('init(validating:)', 'initWithValidating:error:'),
      ('later()', 'laterWithCompletion:'),
      ('wait()', 'waitWithCompletion:'),
      ('fetch(id:)', 'fetchId:completion:'),
      ('total(of:)', 'totalOf:completion:'),
      ('level()', 'level'),
      ('describe(level:)', 'describeLevel:'),
    ]) {
      final x = member('Counter', m);
      expect(x.isGeneratable, isTrue, reason: m);
      if (x.nativeDescriptor != null) {
        expect(x.nativeDescriptor, sel, reason: m);
      }
    }
    expect(out.module.typeById('NABSwiftFixtures.Mood')!.isGeneratable, isTrue);
    expect(
      out.header,
      contains('@property (class, nonatomic, readonly) NSInteger high;'),
    );
    expect(
      out.header,
      contains('- (BOOL)checkLimit:(NSInteger)limit error:(NSError **)error;'),
    );
    expect(
      out.header,
      contains(
        '- (void)fetchId:(NSInteger)id completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion;',
      ),
    );
    expect(
      out.header,
      contains('- (NSDictionary<NSString *, NSNumber *> *)tags;'),
    );
  });

  test('adapter source and Objective-C view match goldens', () {
    final dir = p.join(findRepoRoot(), 'tests', 'golden', 'swift', 'basic');
    final files = {
      'NABSwiftFixturesAdapters.swift': out.swift,
      'NABSwiftFixturesAdapters.h': out.header,
    };
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      files.forEach(
        (n, c) => File(p.join(dir, n))
          ..createSync(recursive: true)
          ..writeAsStringSync(c),
      );
    }
    files.forEach(
      (n, c) => expect(
        c,
        File(p.join(dir, n)).readAsStringSync(),
        reason: '$n differs (UPDATE_GOLDENS=1 to accept)',
      ),
    );
  });

  test('adapter source type-checks against the module', () {
    final f = File(p.join(tmp.path, 'Adapters.swift'))
      ..writeAsStringSync(out.swift);
    final r = Process.runSync('xcrun', [
      '--sdk',
      sdk.name,
      'swiftc',
      '-typecheck',
      '-warnings-as-errors',
      '-target',
      SwiftToolchain(sdk).target,
      '-sdk',
      sdk.path,
      '-I',
      p.join(tmp.path, 'mod'),
      f.path,
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
  });
}
