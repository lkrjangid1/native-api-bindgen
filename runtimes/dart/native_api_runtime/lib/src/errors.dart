import 'package:jni/jni.dart';

/// Thrown when a generated binding is called on a platform version that does
/// not provide the native symbol (diagnostic `E012 AVAILABILITY_MISMATCH`).
///
/// This replaces a JNI `NoSuchMethodError`/`NoClassDefFoundError` crash with a
/// catchable, descriptive exception.
final class NativeApiUnavailableException implements Exception {
  /// Creates the exception.
  const NativeApiUnavailableException(this.symbol, this.required, this.actual);

  /// Native symbol ID, e.g. `android.os.Foo#bar()`.
  final String symbol;

  /// Required platform version (e.g. `36.1`).
  final String required;

  /// Version of the running device.
  final String actual;

  @override
  String toString() =>
      'E012 AVAILABILITY_MISMATCH: $symbol requires Android API $required '
      '(device: $actual)';
}

/// A Java exception thrown across the generated JNI boundary.
///
/// Preserves the native class name, message and Java stack trace. The
/// underlying throwable is available as [throwable] (a JNI global reference
/// managed by `package:jni`).
final class NativeJavaException implements Exception {
  /// Creates the exception.
  NativeJavaException(
    this.className,
    this.message,
    this.javaStackTrace,
    this.throwable,
  );

  /// Converts a `package:jni` [JThrowable].
  factory NativeJavaException.from(JThrowable t) {
    final first = t.javaStackTrace.split('\n').first.trim();
    final colon = first.indexOf(':');
    final className = colon > 0
        ? first.substring(0, colon)
        : (first.isEmpty ? 'java.lang.Throwable' : first);
    return NativeJavaException(className, t.message, t.javaStackTrace, t);
  }

  /// Fully-qualified Java class, e.g. `java.lang.IllegalArgumentException`.
  final String className;

  /// `Throwable.getMessage()`-style text reported by JNI.
  final String message;

  /// Java stack trace text.
  final String javaStackTrace;

  /// Original throwable.
  final JThrowable throwable;

  /// Whether the Java exception is an instance of [binaryName]
  /// (e.g. `java.lang.IllegalStateException`), including subclasses.
  bool isA(String binaryName) {
    final cls = JClass.forName(binaryName.replaceAll('.', '/'));
    try {
      return throwable.isInstanceOf(cls);
    } finally {
      cls.release();
    }
  }

  @override
  String toString() => 'NativeJavaException($className): $message';
}

/// Runs [body], translating Java exceptions into [NativeJavaException].
/// Never swallows exceptions.
T guardJni<T>(T Function() body) {
  try {
    return body();
  } on JThrowable catch (e) {
    throw NativeJavaException.from(e);
  }
}
