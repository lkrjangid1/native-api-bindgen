import 'dart:io';

import 'package:native_api_android/native_api_android.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'context.dart';

/// Detected toolchain facts. All probes run fixed commands with fixed
/// arguments; nothing from configuration or SDK metadata is executed.
final class Toolchain {
  /// Creates toolchain info.
  Toolchain({
    required this.androidSdk,
    required this.jdk,
    required this.dartVersion,
    required this.flutterVersion,
    required this.jniResolved,
    required this.xcodeVersion,
    required this.iosSdkVersion,
  });

  /// Android SDK, if found.
  final AndroidSdk? androidSdk;

  /// JDK, if found.
  final JdkInfo? jdk;

  /// Running Dart version.
  final String dartVersion;

  /// Flutter version, if found.
  final String? flutterVersion;

  /// `jni` version resolved in the project's pubspec.lock.
  final String? jniResolved;

  /// Xcode version (macOS).
  final String? xcodeVersion;

  /// iPhoneOS SDK version (macOS).
  final String? iosSdkVersion;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'android': androidSdk?.toJson(),
    'jdk': jdk?.version,
    'dart': dartVersion,
    'flutter': flutterVersion,
    'jni': jniResolved,
    'xcode': xcodeVersion,
    'iosSdk': iosSdkVersion,
  };
}

String? _run(String exe, List<String> args) {
  try {
    final r = Process.runSync(exe, args, runInShell: Platform.isWindows);
    if (r.exitCode != 0) return null;
    final out = '${r.stdout}'.trim();
    return out.isEmpty ? null : out;
  } on ProcessException {
    return null;
  }
}

/// Detects the toolchain.
Toolchain detectToolchain(CliContext ctx) {
  String? jni;
  final lock = File(p.join(ctx.projectDir, 'pubspec.lock'));
  if (lock.existsSync()) {
    final doc = loadYaml(lock.readAsStringSync());
    if (doc is Map &&
        doc['packages'] is Map &&
        (doc['packages'] as Map)['jni'] is Map) {
      jni = '${((doc['packages'] as Map)['jni'] as Map)['version']}';
    }
  }
  String? flutter;
  final fv = _run('flutter', ['--version', '--machine']);
  if (fv != null) {
    final m = RegExp(r'"frameworkVersion":\s*"([^"]+)"').firstMatch(fv);
    flutter = m?[1];
  }
  return Toolchain(
    androidSdk: AndroidSdkLocator(
      environment: ctx.environment,
    ).locate(configured: ctx.config.android.sdk),
    jdk: detectJdk(environment: ctx.environment),
    dartVersion: Platform.version.split(' ').first,
    flutterVersion: flutter,
    jniResolved: jni,
    xcodeVersion: Platform.isMacOS
        ? _run('xcodebuild', ['-version'])?.split('\n').first
        : null,
    iosSdkVersion: Platform.isMacOS
        ? _run('xcrun', ['--sdk', 'iphoneos', '--show-sdk-version'])
        : null,
  );
}
