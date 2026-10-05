import 'dart:convert';
import 'dart:io';

import 'package:native_api_android/native_api_android.dart';
import 'package:native_api_bindgen/native_api_bindgen.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Captures output of one CLI invocation.
final class Run {
  Run(this.code, this.out, this.err);
  final int code;
  final String out;
  final String err;
}

Future<Run> cli(
  List<String> args, {
  String? cwd,
  Map<String, String>? env,
}) async {
  final tmp = Directory.systemTemp.createTempSync('cli_io');
  final o = File(p.join(tmp.path, 'out')).openWrite();
  final e = File(p.join(tmp.path, 'err')).openWrite();
  final code = await runCli(
    args,
    out: o,
    err: e,
    environment: env,
    workingDirectory: cwd,
  );
  await o.close();
  await e.close();
  final r = Run(
    code,
    File(p.join(tmp.path, 'out')).readAsStringSync(),
    File(p.join(tmp.path, 'err')).readAsStringSync(),
  );
  tmp.deleteSync(recursive: true);
  return r;
}

void main() {
  late Directory project;
  setUp(() => project = Directory.systemTemp.createTempSync('cli_project'));
  tearDown(() => project.deleteSync(recursive: true));

  test('--version and --json', () async {
    final r = await cli(['--json', '--version']);
    expect(r.code, ExitCodes.ok);
    expect(jsonDecode(r.out), {'version': '0.1.0-dev.1'});
  });

  test('init writes safe defaults once', () async {
    final r = await cli(['init'], cwd: project.path);
    expect(r.code, ExitCodes.ok);
    final yaml = File(
      p.join(project.path, 'native_api_bindgen.yaml'),
    ).readAsStringSync();
    expect(yaml, contains('generatedArtifacts: local-only'));
    expect((await cli(['init'], cwd: project.path)).code, ExitCodes.failure);
    expect(
      (await cli(['init', '--force'], cwd: project.path)).code,
      ExitCodes.ok,
    );
  });

  test('iOS: nothing selected is a usage error; diff ios is E015', () async {
    final r = await cli(['--json', 'generate', 'ios'], cwd: project.path);
    // Without Xcode the SDK lookup fails first (E001); with Xcode the empty
    // selection is rejected (E018). Generating everything is never implicit.
    expect(r.code, anyOf(ExitCodes.usage, ExitCodes.failure));
    expect(
      (await cli([
        'diff',
        'ios',
        '--from',
        '1',
        '--to',
        '2',
      ], cwd: project.path)).code,
      ExitCodes.notImplemented,
    );
  });

  group('with Xcode', () {
    final xcode =
        Platform.isMacOS &&
        Process.runSync('xcrun', [
              '--sdk',
              'iphonesimulator',
              '--show-sdk-path',
            ]).exitCode ==
            0;

    test(
      'generate ios writes Dart bindings beside Android output',
      () async {
        final out = Directory(p.join(project.path, 'lib', 'src', 'generated'))
          ..createSync(recursive: true);
        // A file owned by another target's manifest must survive.
        File(
          p.join(out.path, '.native_api_bindgen_manifest'),
        ).writeAsStringSync('android/keep.dart\n');
        final keep = File(p.join(out.path, 'android', 'keep.dart'))
          ..createSync(recursive: true)
          ..writeAsStringSync('// GENERATED CODE - DO NOT MODIFY BY HAND.\n');
        File(p.join(project.path, 'native_api_bindgen.yaml')).writeAsStringSync(
          'platform:\n  ios:\n    frameworks: [Foundation, UIKit]\n'
          '    classes: [UIDevice]\n    depth: 0\n',
        );
        final r = await cli(['--json', 'generate', 'ios'], cwd: project.path);
        expect(r.code, ExitCodes.ok, reason: r.err);
        final json = jsonDecode(r.out) as Map;
        expect(json['files'], contains('apple/uikit.dart'));
        expect(json['bindings'], greaterThan(0));
        final uikit = File(
          p.join(out.path, 'apple', 'uikit.dart'),
        ).readAsStringSync();
        expect(uikit, contains('extension type UIDevice._'));
        expect(keep.existsSync(), isTrue);
        expect(
          File(
            p.join(out.path, '.native_api_bindgen_manifest_ios'),
          ).existsSync(),
          isTrue,
        );
        final inspect = await cli([
          '--json',
          'inspect',
          'ios',
        ], cwd: project.path);
        expect(inspect.code, ExitCodes.ok);
        expect(
          (jsonDecode(inspect.out) as Map)['frameworks'],
          contains('UIKit'),
        );
      },
      skip: xcode ? false : 'Xcode not available',
    );

    test('unknown iOS class is E001', () async {
      final r = await cli([
        '--json',
        'generate',
        'ios',
        '--class',
        'Foundation.NABDoesNotExist',
      ], cwd: project.path);
      expect(r.code, ExitCodes.failure);
      expect(r.out + r.err, contains('E001'));
    }, skip: xcode ? false : 'Xcode not available');
  });

  test('missing SDK fails with E001 and never downloads', () async {
    final r = await cli(
      ['--json', 'generate', 'flutter', '--entry', 'android.content.Intent'],
      cwd: project.path,
      env: {'HOME': project.path},
    );
    expect(r.code, ExitCodes.failure);
    expect(
      (jsonDecode(r.out) as Map)['diagnostic'],
      containsPair('code', 'E001'),
    );
  });

  test('invalid configuration is a usage error with E018', () async {
    File(
      p.join(project.path, 'native_api_bindgen.yaml'),
    ).writeAsStringSync('generation: {mode: turbo}\n');
    final r = await cli(['--json', 'coverage'], cwd: project.path);
    expect(r.code, ExitCodes.usage);
    expect(
      (jsonDecode(r.out) as Map)['diagnostic'],
      containsPair('code', 'E018'),
    );
  });

  test(
    'audit-license: PASS on clean dir, BLOCK (exit 1) on SDK artifacts',
    () async {
      File(
        p.join(project.path, 'a.dart'),
      ).writeAsStringSync('void main() {}\n');
      expect(
        (await cli([
          'audit-license',
          '--no-dependencies',
        ], cwd: project.path)).code,
        ExitCodes.ok,
      );
      File(
        p.join(project.path, 'Foo.class'),
      ).writeAsBytesSync([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 52]);
      final r = await cli([
        '--json',
        'audit-license',
        '--no-dependencies',
      ], cwd: project.path);
      expect(r.code, ExitCodes.failure);
      expect((jsonDecode(r.out) as Map)['status'], 'BLOCK');
    },
  );

  test('unknown command is a usage error', () async {
    expect((await cli(['frobnicate'])).code, ExitCodes.usage);
  });

  group('with a local Android SDK', () {
    final sdk = AndroidSdkLocator().locate();
    final platform = sdk?.select('36') ?? sdk?.select('auto');
    final skip = platform == null ? 'No Android SDK platform installed' : null;
    final api = platform == null ? '' : '${platform.apiLevel}';
    final sel = [
      '--platform',
      api,
      '--entry',
      'android.os.Handler',
      '--entry',
      'android.os.Looper',
      '--depth',
      '0',
    ];

    test(
      'generate → why-generated → why-skipped → coverage → clean',
      () async {
        final g = await cli([
          '--json',
          'generate',
          'flutter',
          ...sel,
        ], cwd: project.path);
        expect(g.code, ExitCodes.ok, reason: g.err);
        final files = ((jsonDecode(g.out) as Map)['files'] as List)
            .cast<String>();
        expect(
          files,
          containsAll(['android/os.dart', 'bindings.dart', 'java/lang.dart']),
        );
        final os = File(
          p.join(project.path, 'lib/src/generated/android/os.dart'),
        ).readAsStringSync();
        expect(os, startsWith('// GENERATED CODE - DO NOT MODIFY BY HAND.'));
        expect(os, contains('// Source SDK: Android API $api'));
        expect(
          os,
          isNot(contains(sdk!.root)),
          reason: 'no machine paths in output',
        );
        expect(os, contains('extension type Handler._'));
        expect(os, contains('extension type Looper._'));

        final why = await cli([
          'why-generated',
          'android.os.Handler#post',
        ], cwd: project.path);
        expect(why.out, contains('Generated as: Handler.post'));
        expect(why.out, contains('Runtime adapter: package:jni method ID'));
        final skipped = await cli([
          'why-skipped',
          'android.os.Handler#dispatchMessage',
        ], cwd: project.path);
        expect(skipped.code, ExitCodes.ok);

        final cov = await cli(['--json', 'coverage'], cwd: project.path);
        expect(
          ((jsonDecode(cov.out) as Map)['generated'] as Map)['classes'],
          greaterThan(0),
        );

        final clean = await cli(['clean'], cwd: project.path);
        expect(clean.code, ExitCodes.ok);
        expect(
          File(
            p.join(project.path, 'lib/src/generated/android/os.dart'),
          ).existsSync(),
          isFalse,
        );
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('generate react-native writes TS, C++ tables and runtime', () async {
      final r = await cli([
        '--json',
        'generate',
        'react-native',
        ...sel,
      ], cwd: project.path);
      expect(r.code, ExitCodes.ok, reason: r.err);
      final files = ((jsonDecode(r.out) as Map)['files'] as List)
          .cast<String>();
      expect(
        files,
        containsAll([
          'src/generated/android/os.ts',
          'cpp/generated/NabBindings.cpp',
          'cpp/runtime/NabRuntime.cpp',
          'specs/NativeApiBindgen.ts',
        ]),
      );
      final ts = File(
        p.join(project.path, 'native-api-bindings/src/generated/android/os.ts'),
      ).readAsStringSync();
      expect(ts, contains('export class Handler extends JavaObject'));
      expect(ts, contains('static getMainLooper()'));
    }, skip: skip);

    test('verify-reproducible', () async {
      final r = await cli([
        '--json',
        'verify-reproducible',
        ...sel,
      ], cwd: project.path);
      expect(r.code, ExitCodes.ok);
      expect((jsonDecode(r.out) as Map)['reproducible'], isTrue);
    }, skip: skip);

    test('inspect, explain and graph', () async {
      final i = await cli([
        '--json',
        'inspect',
        '--platform',
        api,
        'android.net.Uri#parse',
      ], cwd: project.path);
      expect(
        (jsonDecode(i.out) as Map)['id'],
        'android.net.Uri#parse(java.lang.String)',
      );
      final e = await cli([
        'explain',
        '--platform',
        api,
        'android.content.Intent#ACTION_VIEW',
      ], cwd: project.path);
      expect(e.out, contains('android.intent.action.VIEW'));
      final g = await cli([
        'graph',
        '--platform',
        api,
        'android.os.Handler',
      ], cwd: project.path);
      expect(g.out, contains('android.os.Looper'));
    }, skip: skip);
  });
}
