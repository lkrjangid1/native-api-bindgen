/// Test support for native-api-bindgen packages: parses the synthetic
/// Objective-C fixtures against the installed iOS simulator SDK. Not for
/// production use.
library;

import 'dart:io';

import 'package:native_api_ir/native_api_ir.dart';
import 'package:path/path.dart' as p;

import 'src/objc_extractor.dart';
import 'src/xcode_locator.dart';

/// Repository root, located by walking up to the Objective-C fixtures.
String findRepoRoot([String? start]) {
  var dir = Directory(start ?? Directory.current.path).absolute;
  while (true) {
    if (File(fixtureHeader(dir.path)).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'Repository root not found from ${start ?? Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// Path of `fixtures/objective-c/basic/NABFixtures.h` under [root].
String fixtureHeader(String root) =>
    p.join(root, 'fixtures', 'objective-c', 'basic', 'NABFixtures.h');

/// The iOS simulator SDK, or null when Xcode is unavailable (tests skip).
AppleSdk? get testSdk {
  final sdk = XcodeLocator().locate();
  if (sdk == null || !File(sdk.libclangPath).existsSync()) return null;
  return sdk;
}

/// Parses the synthetic fixtures and extracts the `NABFixtures` module.
ApiModule extractObjCFixtures(AppleSdk sdk) {
  final ex = ObjCExtractor(
    libclangPath: sdk.libclangPath,
    sysroot: sdk.path,
    target: 'arm64-apple-ios13.0-simulator',
    sdkVersion: 'fixture',
    fixtureModule: 'NABFixtures',
    sourceKind: 'fixture',
  )..parse(const [], headerFiles: [fixtureHeader(findRepoRoot())]);
  return ex.extract(const ObjCRequest(frameworks: ['NABFixtures'], depth: 0));
}

/// [module] restricted to the fixture's own types, so snapshots do not
/// depend on the installed SDK version.
ApiModule fixtureOnly(ApiModule module) => ApiModule(
  platform: module.platform,
  sdkVersion: module.sdkVersion,
  sourceRevision: module.sourceRevision,
  generatorVersion: module.generatorVersion,
  types: [
    for (final t in module.types)
      if (t.id.startsWith('NABFixtures.')) t,
  ],
  diagnostics: module.diagnostics,
);
