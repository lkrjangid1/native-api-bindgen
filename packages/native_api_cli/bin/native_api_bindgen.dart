import 'dart:io';

import 'package:native_api_bindgen/native_api_bindgen.dart';

Future<void> main(List<String> args) async {
  final code = await runCli(args);
  await stdout.flush();
  await stderr.flush();
  exit(code);
}
