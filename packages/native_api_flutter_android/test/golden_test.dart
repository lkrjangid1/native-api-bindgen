@TestOn('vm')
library;

import 'dart:io';

import 'package:native_api_android/testing.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_android/native_api_flutter_android.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Golden tests: generated Dart for the synthetic fixtures must match
/// `tests/golden/flutter/basic` byte for byte. Regenerate deliberately with
/// `UPDATE_GOLDENS=1` and review the diff.
void main() {
  if (!javacAvailable) {
    test('golden', () {}, skip: 'javac not available');
    return;
  }
  late ApiModule module;
  setUpAll(() {
    final f = fixtureExtractor();
    module = extractFixtures(f.extractor);
    f.classesDir.deleteSync(recursive: true);
  });

  GenerationOutput gen([GenerationMode mode = GenerationMode.strictNative]) =>
      DartJniEmitter(module, options: DartJniOptions(mode: mode)).emit();

  void compareGolden(String name, GenerationOutput out) {
    final dir = p.join(findRepoRoot(), 'tests', 'golden', 'flutter', name);
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
        p.relative(f.path, from: dir).replaceAll(r'\', '/'): f
            .readAsStringSync(),
    };
    expect(out.files.map((f) => f.path).toSet(), expected.keys.toSet());
    for (final f in out.files) {
      expect(
        f.contents,
        expected[f.path],
        reason: '${f.path} differs from golden (UPDATE_GOLDENS=1 to accept)',
      );
    }
  }

  test(
    'strict-native output matches golden',
    () => compareGolden('basic', gen()),
  );
  test(
    'ergonomic-dart output matches golden',
    () => compareGolden('basic_ergonomic', gen(GenerationMode.ergonomicDart)),
  );

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
      for (final n in [t, ...t.methods, ...t.fields]) {
        if (n.isGeneratable && (t.isGeneratable || n == t)) {
          expect(mapped, contains(n.id), reason: n.id);
        } else {
          expect(
            n.diagnostics,
            isNotEmpty,
            reason: 'skipped without reason: ${n.id}',
          );
        }
      }
    }
    expect(
      validateModule(out.module).where((d) => d.severity == Severity.error),
      isEmpty,
    );
  });

  test('target decisions: hidden, protected, abstract ctor, generics', () {
    final m = gen().module;
    expect(
      m.typeById('com.example.fixtures.HiddenClass')!.isGeneratable,
      isFalse,
    );
    final g = m.nodeById('com.example.fixtures.GenericClass#get()')!;
    expect(g.support, SupportStatus.partial);
    expect(
      g.diagnostics.map((d) => d.code),
      contains(DiagnosticCode.unsupportedGeneric),
    );
    expect(
      m.typeById('androidx.annotation.NonNull'),
      isNull,
      reason: 'stubs are outside the fixture package',
    );
  });

  test(
    'golden output passes dart analyze',
    () async {
      final tmp = Directory.systemTemp.createTempSync('golden_analyze');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = findRepoRoot();
      File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('''
name: golden_analyze
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  jni: ^1.0.3
  native_api_runtime:
    path: ${p.join(root, 'runtimes', 'dart', 'native_api_runtime')}
''');
      for (final name in ['basic', 'basic_ergonomic']) {
        final src = Directory(p.join(root, 'tests', 'golden', 'flutter', name));
        for (final f in src.listSync(recursive: true).whereType<File>()) {
          File(
              p.join(tmp.path, 'lib', name, p.relative(f.path, from: src.path)),
            )
            ..createSync(recursive: true)
            ..writeAsStringSync(f.readAsStringSync());
        }
      }
      final get = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
        '--offline',
      ], workingDirectory: tmp.path);
      if (get.exitCode != 0) {
        markTestSkipped(
          'pub get --offline failed (package:jni not cached): ${get.stderr}',
        );
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
