// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:jni/_internal.dart' as jnii;
import 'package:jni/jni.dart';

import 'callbacks.dart';
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
    // A null result (e.g. `String?`) arrives as address 0.
    value = address == 0
        ? null
        : JObject.fromReference(
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

/// Collects a Kotlin `kotlinx.coroutines.flow.Flow` into a Dart [Stream].
///
/// Collection starts when the stream is listened to: `Flow.collect` runs as
/// a suspend call (see [callSuspend]) with a `FlowCollector` implemented in
/// Dart. Each `emit` adds the value (a new reference owned by the listener)
/// and returns immediately, so the flow is not suspended by the Dart side:
/// values are buffered by the stream (no backpressure). The stream closes
/// when the flow completes; a Kotlin exception is delivered as a
/// [NativeJavaException] error. Cancelling the subscription makes the next
/// `emit` throw, which aborts the flow (as Kotlin's `take` does). An endless
/// flow that never emits again keeps running until it does.
///
/// [flow] is released when collection ends.
Stream<JObject?> collectFlow(JObject flow) {
  late final StreamController<JObject?> controller;
  final state = _FlowState();
  controller = StreamController<JObject?>(
    sync: false,
    onListen: () {
      state.controller = controller;
      _collect(flow, state);
    },
    onCancel: () {
      state.cancelled = true;
    },
  );
  return controller.stream;
}

final class _FlowState {
  StreamController<JObject?>? controller;
  bool cancelled = false;
}

/// Thrown into Kotlin from `emit` after the Dart subscription was cancelled.
final class FlowCollectionCancelled implements Exception {
  /// Creates the exception.
  const FlowCollectionCancelled();

  @override
  String toString() => 'Flow collection cancelled by the Dart subscription';
}

final _flowStates = <int, _FlowState>{};

final _collectId = JClass.forName('kotlinx/coroutines/flow/Flow').instanceMethodId(
  'collect',
  '(Lkotlinx/coroutines/flow/FlowCollector;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;',
);

final _unitClass = JClass.forName('kotlin/Unit');
final JObject _unit = _unitClass
    .staticFieldId('INSTANCE', 'Lkotlin/Unit;')
    .get(_unitClass, JObject.type);

const _emitDescriptor =
    'emit(Ljava/lang/Object;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;';

jnii.JObjectPtr _flowInvoke(
  int port,
  jnii.JObjectPtr descriptor,
  jnii.JObjectPtr args,
) {
  final r = _flowInvokeMethod(
    port,
    jnii.MethodInvocation.fromAddresses(0, descriptor.address, args.address),
  );
  NativeCallbacks.wakeEventLoop();
  return r;
}

final _flowInvokePointer =
    Pointer.fromFunction<
      jnii.JObjectPtr Function(Int64, jnii.JObjectPtr, jnii.JObjectPtr)
    >(_flowInvoke);

Pointer<Void> _flowInvokeMethod(int port, jnii.MethodInvocation i) {
  final d = i.methodDescriptor.toDartString(releaseOriginal: true);
  final a = i.args;
  if (d != _emitDescriptor) return nullptr;
  final s = _flowStates[port];
  if (s == null || s.cancelled) {
    return jnii.ProtectedJniExtensions.newDartException(
      const FlowCollectionCancelled(),
    );
  }
  s.controller!.add(a![0]);
  return _unit.as(JObject.type).reference.toPointer();
}

Future<void> _collect(JObject flow, _FlowState state) async {
  late final RawReceivePort p;
  p = RawReceivePort((Object? m) {
    if (m == null) {
      _flowStates.remove(p.sendPort.nativePort);
      p.close();
      return;
    }
    final i = jnii.MethodInvocation.fromMessage(m as List<dynamic>);
    final r = _flowInvokeMethod(p.sendPort.nativePort, i);
    i.args?.release();
    jnii.ProtectedJniExtensions.returnResult(i.result, r);
  });
  _flowStates[p.sendPort.nativePort] = state;
  final implementer = JImplementer();
  implementer.add(
    'kotlinx.coroutines.flow.FlowCollector',
    p,
    _flowInvokePointer,
    const [],
  );
  final collector = implementer.implement<JObject>();
  implementer.release();
  final controller = state.controller!;
  try {
    final r = await callSuspend(
      (c) => _collectId.callNullable(flow, JObject.type, [collector, c]),
    );
    r?.release();
  } catch (e, st) {
    if (!state.cancelled) controller.addError(e, st);
  } finally {
    collector.release();
    flow.release();
    state.cancelled = true;
    if (!controller.isClosed) await controller.close();
  }
}
