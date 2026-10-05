import 'dart:io';

import 'package:native_api_android/testing.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_react_native_android/native_api_react_native_android.dart';

void main(List<String> args) {
  final f = fixtureExtractor();
  final module = extractFixtures(f.extractor);
  f.classesDir.deleteSync(recursive: true);
  final out = RnJsiEmitter(module).emit();
  writeGeneration(OutputGuard(args.first), out);
  stdout.writeln('files=${out.files.length} bindings=${out.bindings.length}');
}
