import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_ios/native_api_flutter_ios.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ios/native_api_ios.dart';
import 'package:path/path.dart' as p;

/// Generates Dart bindings for fixtures/objective-c/basic into [args.first].
void main(List<String> args) {
  final sdk = XcodeLocator().locate()!;
  var root = Directory.current;
  while (!File(
    p.join(root.path, 'fixtures', 'objective-c', 'basic', 'NABFixtures.h'),
  ).existsSync()) {
    root = root.parent;
  }
  final ex = ObjCExtractor(
    libclangPath: sdk.libclangPath,
    sysroot: sdk.path,
    target: 'arm64-apple-ios13.0-simulator',
    sdkVersion: 'fixture',
    fixtureModule: 'NABFixtures',
    sourceKind: 'fixture',
  );
  ex.parse(
    const [],
    headerFiles: [
      p.join(root.path, 'fixtures', 'objective-c', 'basic', 'NABFixtures.h'),
    ],
  );
  final module = ex.extract(
    const ObjCRequest(frameworks: ['NABFixtures'], depth: 0),
  );
  final out = DartObjCEmitter(module).emit();
  writeGeneration(OutputGuard(args.first), out);
  stdout.writeln('files=${out.files.length} bindings=${out.bindings.length}');
}
