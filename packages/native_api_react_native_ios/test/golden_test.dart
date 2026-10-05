@TestOn('mac-os')
library;

import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ios/testing.dart';
import 'package:native_api_ir/native_api_ir.dart';
import 'package:native_api_react_native_ios/native_api_react_native_ios.dart';
import 'package:native_api_react_native_ios/src/runtime_sources.g.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Golden tests for the React Native iOS target over the synthetic
/// Objective-C fixtures (`tests/golden/react-native-ios/<mode>`; runtime
/// files are checked separately against `runtimes/`). Regenerate
/// deliberately with `UPDATE_GOLDENS=1` and review the diff.
void main() {
  final sdk = testSdk;
  if (sdk == null) {
    test('golden', () {}, skip: 'Xcode/libclang not available');
    return;
  }
  late ApiModule module;
  setUpAll(() => module = fixtureOnly(extractObjCFixtures(sdk)));

  GenerationOutput gen([TypescriptMode mode = TypescriptMode.strict]) =>
      RnObjCEmitter(module, options: RnObjCOptions(mode: mode)).emit();

  void compare(String name, GenerationOutput out) {
    final dir = p.join(
      findRepoRoot(),
      'tests',
      'golden',
      'react-native-ios',
      name,
    );
    final files = out.files
        .where((f) => !runtimeSources.containsKey(f.path))
        .toList();
    if (Platform.environment['UPDATE_GOLDENS'] == '1') {
      if (Directory(dir).existsSync()) {
        Directory(dir).deleteSync(recursive: true);
      }
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
        p.relative(f.path, from: dir): f.readAsStringSync(),
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

  test('embedded runtime matches runtimes/', () {
    const sources = {
      'cpp/runtime/NativeApiBindgen.h': 'runtimes/jsi/cpp/NativeApiBindgen.h',
      'cpp/runtime/NativeApiBindgen.cpp':
          'runtimes/jsi/cpp/NativeApiBindgen.cpp',
      'cpp/runtime-objc/NabObjCRuntime.h': 'runtimes/jsi/objc/NabObjCRuntime.h',
      'cpp/runtime-objc/NabObjCRuntime.mm':
          'runtimes/jsi/objc/NabObjCRuntime.mm',
      'cpp/runtime-objc/NabModuleProvider.h':
          'runtimes/jsi/objc/NabModuleProvider.h',
      'cpp/runtime-objc/NabModuleProvider.mm':
          'runtimes/jsi/objc/NabModuleProvider.mm',
      'src/runtime-objc.ts': 'runtimes/jsi/ts/runtime-objc.ts',
      'specs/NativeApiBindgen.ts': 'runtimes/jsi/ts/specs/NativeApiBindgen.ts',
    };
    expect(runtimeSources.keys.toSet(), sources.keys.toSet());
    sources.forEach((out, src) {
      expect(
        runtimeSources[out],
        File(p.join(findRepoRoot(), src)).readAsStringSync(),
        reason: 'run tool/embed_runtime.dart after editing $src',
      );
    });
  });

  test('deterministic', () {
    final a = gen(), b = gen();
    expect(
      [for (final f in a.files) f.contents],
      [for (final f in b.files) f.contents],
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
          expect(n.diagnostics, isNotEmpty, reason: 'no reason: ${n.id}');
        }
      }
    }
  });

  test('member tables: selectors, conversion codes, flags', () {
    final cpp = gen().files
        .firstWhere((f) => f.path == 'cpp/generated/NabBindingsObjC.cpp')
        .contents;
    expect(
      cpp,
      contains(
        '{"-saveToPath:error:", "saveToPath:error:", "zs", MemberKind::InstanceMethod, 8}',
      ),
    );
    expect(
      cpp,
      contains(
        '{"-initWithName:", "initWithName:", "os", MemberKind::InstanceMethod, 2}',
      ),
    );
    expect(
      cpp,
      contains(
        '{"P-frame=", "setFrame:", "vSNABRect;", MemberKind::InstanceSetter, 0}',
      ),
    );
    expect(cpp, contains('{"NABRect", k_f_NABRect, k_s_NABRect, 2}'));
    expect(
      cpp,
      contains('const char* const k_s_NABRect[] = {"NABPoint", "NABPoint"};'),
    );
    expect(cpp, isNot(contains('runWithCompletion')), reason: 'blocks: E004');
    expect(cpp, isNot(contains('_privateHelper')));
  });

  test(
    'TypeScript type-checks and Objective-C++ compiles',
    () async {
      final root = findRepoRoot();
      final rnApp = p.join(root, 'examples', 'react-native', 'slice');
      final tsc = File(p.join(rnApp, 'node_modules', '.bin', 'tsc'));
      if (!tsc.existsSync()) {
        markTestSkipped(
          'examples/react-native/slice/node_modules not installed',
        );
        return;
      }
      final tmp = Directory.systemTemp.createTempSync('rn_ios_golden');
      addTearDown(() => tmp.deleteSync(recursive: true));
      for (final mode in TypescriptMode.values) {
        final dir = Directory(p.join(tmp.path, mode.key))..createSync();
        writeGeneration(OutputGuard(dir.path), gen(mode));
        Link(
          p.join(dir.path, 'node_modules'),
        ).createSync(p.join(rnApp, 'node_modules'));
        File(p.join(dir.path, 'tsconfig.json')).writeAsStringSync(
          '{"extends": "@react-native/typescript-config", "compilerOptions": {"noEmit": true, "strict": true, "skipLibCheck": true}, '
          '"include": ["ios.ts", "src/**/*.ts", "specs/**/*.ts"]}',
        );
        final t = await Process.run(tsc.path, [
          '-p',
          'tsconfig.json',
        ], workingDirectory: dir.path);
        expect(t.exitCode, 0, reason: '${mode.key}: ${t.stdout}${t.stderr}');
      }
      final rc = p.join(rnApp, 'node_modules', 'react-native', 'ReactCommon');
      final lib = p.join(tmp.path, TypescriptMode.strict.key);
      for (final f in [
        'cpp/runtime-objc/NabObjCRuntime.mm',
        'cpp/generated/NabBindingsObjC.cpp',
      ]) {
        final r = await Process.run('xcrun', [
          '--sdk',
          'iphonesimulator',
          'clang++',
          '-std=c++20',
          '-fobjc-arc',
          if (f.endsWith('.mm')) ...['-x', 'objective-c++'],
          '-fsyntax-only',
          '-Wall',
          '-Wextra',
          '-Werror',
          '-Wno-unused-parameter',
          '-target',
          'arm64-apple-ios15.0-simulator',
          '-I${p.join(lib, 'cpp', 'runtime-objc')}',
          '-I${p.join(rc, 'jsi')}',
          '-I${p.join(rc, 'callinvoker')}',
          '-I$rc',
          p.join(lib, f),
        ]);
        expect(r.exitCode, 0, reason: '$f:\n${r.stderr}');
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
