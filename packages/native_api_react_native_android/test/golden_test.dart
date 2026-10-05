@TestOn('vm')
library;

import 'dart:io';

import 'package:native_api_android/testing.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:native_api_react_native_android/native_api_react_native_android.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/embed_runtime.dart' as embed;

/// Golden + determinism tests for the React Native target. Regenerate with
/// `UPDATE_GOLDENS=1` and review the diff.
void main() {
  test('embedded runtime sources match runtimes/', () {
    final root = findRepoRoot();
    expect(runtimeSources.keys.toSet(), embed.files.keys.toSet());
    embed.files.forEach((out, src) {
      expect(
        runtimeSources[out],
        File(p.join(root, src)).readAsStringSync(),
        reason: '$src changed: run tool/embed_runtime.dart',
      );
    });
  });

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

  GenerationOutput gen([TypescriptMode mode = TypescriptMode.strict]) =>
      RnJsiEmitter(module, options: RnJsiOptions(mode: mode)).emit();

  void compare(String name, GenerationOutput out) {
    final dir = p.join(findRepoRoot(), 'tests', 'golden', 'react-native', name);
    // Runtime copies are verified separately; goldens cover generated output.
    final files = out.files
        .where((f) => !runtimeSources.containsKey(f.path))
        .toList();
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      if (Directory(dir).existsSync())
        Directory(dir).deleteSync(recursive: true);
      for (final f in files) {
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
    expect(files.map((f) => f.path).toSet(), expected.keys.toSet());
    for (final f in files) {
      expect(
        f.contents,
        expected[f.path],
        reason: '${f.path} differs (UPDATE_GOLDENS=1 to accept)',
      );
    }
  }

  test(
    'strict-typescript output matches golden',
    () => compare('basic', gen()),
  );
  test(
    'ergonomic-typescript output matches golden',
    () => compare('basic_ergonomic', gen(TypescriptMode.ergonomic)),
  );

  test('deterministic', () {
    final a = gen(), b = gen();
    expect(
      [for (final f in a.files) f.contents],
      [for (final f in b.files) f.contents],
    );
  });

  test('long constants: bigint in strict, number in ergonomic', () {
    String ts(GenerationOutput o) => o.files
        .firstWhere((f) => f.path == 'src/generated/bindings.ts')
        .contents;
    expect(
      ts(gen()),
      contains('static readonly BIG: bigint = 9223372036854775807n;'),
    );
    expect(ts(gen(TypescriptMode.ergonomic)), contains('E011 ABI_MISMATCH'));
  });

  test('C++ tables are sorted and keyed by name + descriptor', () {
    final cpp = gen().files
        .firstWhere((f) => f.path == 'cpp/generated/NabBindings.cpp')
        .contents;
    final keys = RegExp(
      r'^    \{"([^"]+)", "[^"]+", (k_|nullptr)',
      multiLine: true,
    ).allMatches(cpp).map((m) => m[1]!).toList();
    expect(keys, isNotEmpty);
    final sorted = [...keys]..sort();
    expect(keys, sorted);
    expect(
      cpp,
      contains(
        r'{"add(int,int)I", "add", "(II)I", MemberKind::InstanceMethod}',
      ),
    );
    expect(cpp, isNot(contains('HiddenClass')));
  });

  test(
    'generated TypeScript type-checks and C++ compiles (when toolchains are present)',
    () async {
      final root = findRepoRoot();
      final rnApp = p.join(root, 'examples', 'react-native', 'android_slice');
      final tsc = File(p.join(rnApp, 'node_modules', '.bin', 'tsc'));
      if (!tsc.existsSync()) {
        markTestSkipped(
          'examples/react-native/android_slice/node_modules not installed',
        );
        return;
      }
      final tmp = Directory.systemTemp.createTempSync('rn_golden');
      addTearDown(() => tmp.deleteSync(recursive: true));
      writeGeneration(OutputGuard(tmp.path), gen());
      Link(
        p.join(tmp.path, 'node_modules'),
      ).createSync(p.join(rnApp, 'node_modules'));
      File(p.join(tmp.path, 'tsconfig.json')).writeAsStringSync(
        '{"extends": "@react-native/typescript-config", "compilerOptions": {"noEmit": true, "strict": true, "skipLibCheck": true}, '
        '"include": ["index.ts", "src/**/*.ts", "specs/**/*.ts"]}',
      );
      final t = await Process.run(tsc.path, [
        '-p',
        'tsconfig.json',
      ], workingDirectory: tmp.path);
      expect(t.exitCode, 0, reason: '${t.stdout}${t.stderr}');

      final javaHome = Platform.environment['JAVA_HOME'];
      final jdk =
          javaHome != null &&
              Directory(p.join(javaHome, 'include')).existsSync()
          ? javaHome
          : null;
      if (jdk == null) {
        markTestSkipped('JAVA_HOME not set; skipping C++ syntax check');
        return;
      }
      final rc = p.join(rnApp, 'node_modules', 'react-native', 'ReactCommon');
      for (final f in [
        'cpp/runtime/NabRuntime.cpp',
        'cpp/generated/NabBindings.cpp',
      ]) {
        final r = await Process.run('clang++', [
          '-std=c++20',
          '-fsyntax-only',
          '-Wall',
          '-Wextra',
          '-Werror',
          '-I${p.join(tmp.path, 'cpp', 'runtime')}',
          '-I${p.join(rc, 'jsi')}',
          '-I${p.join(rc, 'callinvoker')}',
          '-I${p.join(jdk, 'include')}',
          '-I${p.join(jdk, 'include', Platform.isMacOS ? 'darwin' : 'linux')}',
          p.join(tmp.path, f),
        ]);
        expect(r.exitCode, 0, reason: '$f:\n${r.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
