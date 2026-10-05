// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:ffi';
import 'dart:isolate';

import 'package:jni/_internal.dart' as jnii;
import 'package:jni/jni.dart';

import 'errors.dart';

/// Calls a Kotlin `suspend` function and completes with its result.
///
/// A suspend function compiles to a JVM method whose last parameter is a
/// `kotlin.coroutines.Continuation`. [invoke] performs the JNI call with the
/// given continuation (a `PortContinuation` from `package:jni` that posts
/// the result to a Dart port) and returns the raw result: either the value
/// itself, or `COROUTINE_SUSPENDED`, in which case the value arrives later.
/// A Kotlin exception completes the future with [NativeJavaException].
Future<JObject?> callSuspend(
  JObject? Function(JObject continuation) invoke,
) async {
  final port = ReceivePort();
  final continuation = JObject.fromReference(
    jnii.ProtectedJniExtensions.newPortContinuation(port),
  );
  JObject? result;
  try {
    result = guardJni(() => invoke(continuation));
  } catch (_) {
    port.close();
    rethrow;
  } finally {
    continuation.release();
  }
  JObject? value;
  if (result != null && result.isInstanceOf(jnii.coroutineSingletonsClass)) {
    result.release();
    final address = await port.first as int;
    value = JObject.fromReference(
      jnii.JGlobalReference(Pointer<Void>.fromAddress(address)),
    );
  } else {
    port.close();
    value = result;
  }
  if (value != null && value.isInstanceOf(jnii.result$FailureClass)) {
    final error = jnii.failureExceptionField.get(value, JObject.type);
    value.release();
    // Throws the Kotlin exception as NativeJavaException.
    guardJni<void>(() => Jni.throwException(error.reference.toPointer()));
    throw StateError('unreachable: Kotlin failure without exception');
  }
  return value;
}
