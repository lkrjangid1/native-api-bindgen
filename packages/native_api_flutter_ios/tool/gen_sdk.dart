import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_ios/native_api_flutter_ios.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ios/native_api_ios.dart';

/// Usage: `dart run tool/gen_sdk.dart <out> [frameworks...]`
void main(List<String> args) {
  final sdk = XcodeLocator().locate()!;
  final fws = args.length > 1 ? args.sublist(1) : ['Foundation', 'UIKit'];
  final sw = Stopwatch()..start();
  final ex = ObjCExtractor(
    libclangPath: sdk.libclangPath,
    sysroot: sdk.path,
    target: 'arm64-apple-ios13.0-simulator',
    sdkVersion: sdk.version,
  );
  ex.parse([for (final f in fws) '$f/$f.h']);
  final module = ex.extract(ObjCRequest(frameworks: fws, depth: 0));
  final out = DartObjCEmitter(module).emit();
  writeGeneration(OutputGuard(args.first), out);
  stdout.writeln(
    '${sw.elapsedMilliseconds} ms: types=${module.types.length} files=${out.files.length} bindings=${out.bindings.length}',
  );
}
