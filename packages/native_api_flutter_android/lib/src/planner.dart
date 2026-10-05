import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';

/// Flutter/Dart target planning; identical to [planJvmTarget].
ApiModule planDartJni(ApiModule module, {bool callbacks = true}) =>
    planJvmTarget(module, callbacks: callbacks);
