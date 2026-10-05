import 'dart:io';

import 'package:path/path.dart' as p;

/// A detected Apple SDK (from the locally installed Xcode).
final class AppleSdk {
  /// Creates SDK info.
  const AppleSdk({
    required this.name,
    required this.path,
    required this.version,
    required this.developerDir,
    required this.libclangPath,
    required this.xcodeVersion,
  });

  /// `iphonesimulator` or `iphoneos`.
  final String name;

  /// SDK root (absolute). Never embedded in generated output.
  final String path;

  /// SDK version, e.g. `27.0`.
  final String version;

  /// `xcode-select -p`.
  final String developerDir;

  /// libclang from the Xcode toolchain.
  final String libclangPath;

  /// `xcodebuild -version` first line.
  final String xcodeVersion;

  /// Absolute directory of a framework's headers.
  String frameworkHeaders(String framework) => p.join(
    path,
    'System',
    'Library',
    'Frameworks',
    '$framework.framework',
    'Headers',
  );

  /// JSON form (no absolute SDK path).
  Map<String, Object?> toJson() => {
    'sdk': name,
    'version': version,
    'xcode': xcodeVersion,
    'libclang': File(libclangPath).existsSync(),
  };
}

/// Locates Apple SDKs with the official command-line tools only
/// (`xcode-select`, `xcrun`, `xcodebuild`). Never downloads anything.
final class XcodeLocator {
  String? _run(String exe, List<String> args) {
    try {
      final r = Process.runSync(exe, args);
      if (r.exitCode != 0) return null;
      final out = '${r.stdout}'.trim();
      return out.isEmpty ? null : out;
    } on ProcessException {
      return null;
    }
  }

  /// Locates [sdkName] (`iphonesimulator` by default) or returns null when
  /// not on macOS or Xcode is not installed.
  AppleSdk? locate({String sdkName = 'iphonesimulator'}) {
    if (!Platform.isMacOS) return null;
    final dev = _run('xcode-select', ['-p']);
    final path = _run('xcrun', ['--sdk', sdkName, '--show-sdk-path']);
    final version = _run('xcrun', ['--sdk', sdkName, '--show-sdk-version']);
    if (dev == null || path == null || version == null) return null;
    final libclang = p.join(
      dev,
      'Toolchains',
      'XcodeDefault.xctoolchain',
      'usr',
      'lib',
      'libclang.dylib',
    );
    return AppleSdk(
      name: sdkName,
      path: path,
      version: version,
      developerDir: dev,
      libclangPath: libclang,
      xcodeVersion:
          _run('xcodebuild', ['-version'])?.split('\n').first ?? 'unknown',
    );
  }
}
