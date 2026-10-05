import 'dart:io';

import 'package:native_api_android/testing.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_android/native_api_flutter_android.dart';
import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';

void main(List<String> args) {
  final f = fixtureExtractor();
  final module = extractFixtures(f.extractor);
  f.classesDir.deleteSync(recursive: true);
  final out = DartJniEmitter(
    module,
    options: DartJniOptions(
      minApi: const ApiVersion(24),
      mode: args.length > 1 && args[1] == 'ergonomic'
          ? GenerationMode.ergonomicDart
          : GenerationMode.strictNative,
    ),
  ).emit();
  final guard = OutputGuard(args.first);
  writeGeneration(guard, out);
  stdout.writeln('files=${out.files.length} bindings=${out.bindings.length}');
}
