import 'dart:io';

import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ios/testing.dart';
import 'package:native_api_react_native_ios/native_api_react_native_ios.dart';

/// Writes the React Native iOS output for the Objective-C fixtures to
/// [args.first] (for manual inspection).
void main(List<String> args) {
  final module = fixtureOnly(extractObjCFixtures(testSdk!));
  final out = RnObjCEmitter(module).emit();
  writeGeneration(OutputGuard(args.first), out);
  stdout.writeln('files=${out.files.length} bindings=${out.bindings.length}');
}
