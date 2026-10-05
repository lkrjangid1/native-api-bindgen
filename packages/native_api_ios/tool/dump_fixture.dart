import 'dart:io';

import 'package:native_api_ios/native_api_ios.dart';

void main(List<String> args) {
  final sdk = XcodeLocator().locate()!;
  final ex = ObjCExtractor(
    libclangPath: sdk.libclangPath,
    sysroot: sdk.path,
    target: 'arm64-apple-ios13.0-simulator',
    sdkVersion: sdk.version,
    fixtureModule: 'NABFixtures',
    sourceKind: 'fixture',
  );
  final sw = Stopwatch()..start();
  ex.parse(
    args.length > 1 ? args.sublist(1) : const [],
    headerFiles: [if (args.isNotEmpty) File(args.first).absolute.path],
  );
  final m = ex.extract(
    const ObjCRequest(frameworks: ['NABFixtures'], depth: 0),
  );
  stderr.writeln(
    'parse+extract ${sw.elapsedMilliseconds} ms, types=${m.types.length}',
  );
  stdout.write(m.toCanonicalJson());
}
