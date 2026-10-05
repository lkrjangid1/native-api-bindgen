import 'package:native_api_generator/native_api_generator.dart';
import 'package:native_api_ir/native_api_ir.dart';

/// Flutter/Dart target planning: [planJvmTarget] with Kotlin suspend
/// support, Dart generics and the types `package:jni` already wraps.
ApiModule planDartJni(ApiModule module, {bool callbacks = true}) =>
    planJvmTarget(
      module,
      callbacks: callbacks,
      suspend: true,
      generics: true,
      externalTypes: jniBuiltinTypes.keys.toSet(),
    );
