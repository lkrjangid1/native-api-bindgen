import 'dart:io';

import 'package:path/path.dart' as p;

import 'xcode_locator.dart';

/// Thrown when the Swift toolchain fails.
final class SwiftToolchainException implements Exception {
  /// Creates the exception.
  SwiftToolchainException(this.message);

  /// Tool output.
  final String message;

  @override
  String toString() => 'SwiftToolchainException: $message';
}

/// Runs the official Swift tools from the selected Xcode (`xcrun swiftc`,
/// `xcrun swift-symbolgraph-extract`). Nothing is downloaded.
final class SwiftToolchain {
  /// Creates a toolchain for [sdk] targeting `arm64-apple-ios<minIos>`.
  SwiftToolchain(this.sdk, {this.minIos = '15.0'});

  /// SDK.
  final AppleSdk sdk;

  /// Deployment target.
  final String minIos;

  /// Clang/Swift target triple.
  String get target => sdk.name == 'iphoneos'
      ? 'arm64-apple-ios$minIos'
      : 'arm64-apple-ios$minIos-simulator';

  ProcessResult _run(List<String> args) {
    final r = Process.runSync('xcrun', ['--sdk', sdk.name, ...args]);
    if (r.exitCode != 0) {
      throw SwiftToolchainException(
        '${args.first}: ${r.stderr}${r.stdout}'.trim(),
      );
    }
    return r;
  }

  /// Compiles [sources] into `<outDir>/<module>.swiftmodule` (interface only).
  String emitModule(String module, List<String> sources, String outDir) {
    Directory(outDir).createSync(recursive: true);
    final path = p.join(outDir, '$module.swiftmodule');
    _run([
      'swiftc',
      '-emit-module',
      '-parse-as-library',
      '-module-name',
      module,
      '-target',
      target,
      '-sdk',
      sdk.path,
      '-emit-module-path',
      path,
      ...sources,
    ]);
    return path;
  }

  /// Extracts the public symbol graph of [module] (an SDK module, or one in
  /// [includeDirs]) into [outDir]; returns `<outDir>/<module>.symbols.json`.
  String extractSymbolGraph(
    String module,
    String outDir, {
    List<String> includeDirs = const [],
  }) {
    Directory(outDir).createSync(recursive: true);
    _run([
      'swift-symbolgraph-extract',
      '-module-name',
      module,
      '-target',
      target,
      '-sdk',
      sdk.path,
      for (final d in includeDirs) ...['-I', d],
      '-output-dir',
      outDir,
      '-minimum-access-level',
      'public',
    ]);
    final out = p.join(outDir, '$module.symbols.json');
    if (!File(out).existsSync()) {
      throw SwiftToolchainException('no symbol graph produced for $module');
    }
    return out;
  }
}
