@TestOn('mac-os')
library;

import 'dart:io';

import 'package:native_api_flutter_ios/native_api_flutter_ios.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ios/testing.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Golden tests: Dart generated for the synthetic Objective-C fixtures must
/// match `tests/golden/flutter-ios/basic` byte for byte. Only the fixture's
/// own types are emitted so the goldens do not depend on the installed SDK.
/// Regenerate deliberately with `UPDATE_GOLDENS=1` and review the diff.
void main() {
  final sdk = testSdk;
  if (sdk == null) {
    test('golden', () {}, skip: 'Xcode/libclang not available');
    return;
  }
  late ApiModule module;
  setUpAll(() => module = fixtureOnly(extractObjCFixtures(sdk)));

  GenerationOutput gen() => DartObjCEmitter(module).emit();
  final goldenDir = p.join(findRepoRoot(), 'tests', 'golden', 'flutter-ios');

  test('output matches golden', () {
    final out = gen();
    final dir = p.join(goldenDir, 'basic');
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      if (Directory(dir).existsSync()) {
        Directory(dir).deleteSync(recursive: true);
      }
      for (final f in out.files) {
        File(p.join(dir, f.path))
          ..createSync(recursive: true)
          ..writeAsStringSync(f.contents);
      }
    }
    final expected = {
      for (final f in Directory(
        dir,
      ).listSync(recursive: true).whereType<File>())
        p.relative(f.path, from: dir): f.readAsStringSync(),
    };
    expect(out.files.map((f) => f.path).toSet(), expected.keys.toSet());
    for (final f in out.files) {
      expect(
        f.contents,
        expected[f.path],
        reason: '${f.path} differs from golden (UPDATE_GOLDENS=1 to accept)',
      );
    }
  });

  test('generation is deterministic', () {
    final a = gen(), b = gen();
    expect(
      [for (final f in a.files) f.contents],
      [for (final f in b.files) f.contents],
    );
    expect(
      a.bindings.map((e) => e.toJson()).toList(),
      b.bindings.map((e) => e.toJson()).toList(),
    );
  });

  test('every generated member is traceable and every skip has a reason', () {
    final out = gen();
    final mapped = out.bindings.map((b) => b.symbolId).toSet();
    for (final t in out.module.types) {
      if (isRuntimeProvided(t.id)) continue;
      for (final n in [t, ...t.methods, ...t.fields]) {
        if (n.isGeneratable && (t.isGeneratable || n == t)) {
          expect(mapped, contains(n.id), reason: n.id);
        } else {
          expect(n.diagnostics, isNotEmpty, reason: 'no reason: ${n.id}');
        }
      }
    }
  });

  test(
    'target decisions: blocks, NSError**, variadic, private, unavailable',
    () {
      final m = gen().module;
      ApiNode node(String id) => m.nodeById('NABFixtures.$id')!;
      List<DiagnosticCode> codes(String id) => [
        for (final d in node(id).diagnostics) d.code,
      ];
      expect(node('NABThing#-runWithCompletion:').isGeneratable, isFalse);
      expect(
        codes('NABThing#-runWithCompletion:'),
        contains(DiagnosticCode.unsupportedCallback),
      );
      expect(
        node('NABThing#-saveToPath:error:').support,
        SupportStatus.supported,
      );
      expect(node('NABThing#-log:').isGeneratable, isFalse);
      expect(node('NABThing#-_privateHelper').isGeneratable, isFalse);
      expect(node('NABMacOnly').isGeneratable, isFalse);
    },
  );

  test('no absolute SDK path in the output', () {
    for (final f in gen().files) {
      expect(f.contents, isNot(contains(sdk.path)), reason: f.path);
    }
  });

  test(
    'golden output passes dart analyze',
    () async {
      final tmp = Directory.systemTemp.createTempSync('golden_ios_analyze');
      addTearDown(() => tmp.deleteSync(recursive: true));
      File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('''
name: golden_ios_analyze
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  ffi: ^2.1.3
  objective_c: ^9.5.0
''');
      final src = Directory(p.join(goldenDir, 'basic'));
      for (final f in src.listSync(recursive: true).whereType<File>()) {
        File(p.join(tmp.path, 'lib', p.relative(f.path, from: src.path)))
          ..createSync(recursive: true)
          ..writeAsStringSync(f.readAsStringSync());
      }
      final get = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: tmp.path);
      if (get.exitCode != 0) {
        markTestSkipped('objective_c not cached: ${get.stderr}');
        return;
      }
      final r = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        '--fatal-infos',
        'lib',
      ], workingDirectory: tmp.path);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
