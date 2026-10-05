import 'dart:io';

import 'package:native_api_android/testing.dart';
import 'package:native_api_core/native_api_core.dart';
import 'package:native_api_flutter_android/native_api_flutter_android.dart';
import 'package:native_api_generator/native_api_generator.dart';

/// Writes Dart bindings for the Kotlin fixture jar to [args.first].
void main(List<String> args) {
  final jar = kotlinFixtureJar();
  if (jar == null) {
    stderr.writeln('fixtures/kotlin/basic/build/libs/kfixtures.jar not built');
    exit(1);
  }
  final out = DartJniEmitter(extractKotlinFixtures(jar)).emit();
  writeGeneration(
    OutputGuard(args.first),
    out,
    manifestName: '.native_api_bindgen_manifest_kotlin',
  );
  stdout.writeln('files=${out.files.length} bindings=${out.bindings.length}');
}
