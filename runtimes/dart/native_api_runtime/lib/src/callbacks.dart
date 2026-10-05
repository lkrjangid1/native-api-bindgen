import 'dart:async';

/// What generated callback proxies do when a Dart implementation throws.
enum CallbackErrorPolicy {
  /// For `void` callbacks: report the error to the current zone's uncaught
  /// error handler (in Flutter: `PlatformDispatcher.onError`) and return
  /// normally to Java, so a Dart bug cannot crash the Java thread (e.g. the
  /// main Looper). Non-void callbacks always propagate (there is no safe
  /// default return value).
  reportVoidCallbacks,

  /// Always propagate the error to Java as an exception thrown from the
  /// proxy method (Java semantics: uncaught exceptions may terminate the
  /// calling thread).
  propagateToJava,
}

/// Global callback error handling used by generated code (TRD §59).
abstract final class NativeCallbacks {
  /// Current policy.
  static CallbackErrorPolicy policy = CallbackErrorPolicy.reportVoidCallbacks;

  /// Optional observer for every callback error (both policies).
  static void Function(Object error, StackTrace stack, String symbol)? onError;

  /// Called by generated proxies when a `void` callback throws. Returns true
  /// if the error was reported and must not be propagated to Java.
  static bool handleVoidCallbackError(
    Object error,
    StackTrace stack,
    String symbol,
  ) {
    onError?.call(error, stack, symbol);
    if (policy != CallbackErrorPolicy.reportVoidCallbacks) return false;
    Zone.current.handleUncaughtError(NativeCallbackError(symbol, error), stack);
    return true;
  }

  /// Called by generated trampolines after Java invoked a Dart callback
  /// synchronously on the isolate's own thread (e.g. Flutter's platform
  /// thread). In that path no Dart event is being processed, so microtasks
  /// scheduled by the callback (such as completing a `Completer`) would wait
  /// for the next unrelated event. Scheduling an empty timer wakes the event
  /// loop so they run promptly.
  static void wakeEventLoop() => Timer.run(_noop);

  static void _noop() {}

  /// Called by generated proxies when a non-void callback throws (the error
  /// is then propagated to Java).
  static void reportPropagated(Object error, StackTrace stack, String symbol) =>
      onError?.call(error, stack, symbol);
}

/// Wraps an error thrown by a Dart callback implementation.
final class NativeCallbackError implements Exception {
  /// Creates the error.
  const NativeCallbackError(this.symbol, this.error);

  /// Native callback method, e.g. `java.lang.Runnable#run()`.
  final String symbol;

  /// Original error.
  final Object error;

  @override
  String toString() => 'Error in Dart implementation of $symbol: $error';
}
