import 'package:jni/jni.dart';

/// Lifecycle helpers for generated native handles (TRD §15).
///
/// Generated objects are `package:jni` global references: they are released
/// automatically by a native finalizer when garbage-collected, and may be
/// released explicitly and early with `release()`. Use after release throws
/// `UseAfterReleaseError`; double release throws `DoubleReleaseError`.
/// [dispose] provides idempotent explicit disposal.
extension NativeHandle on JObject {
  /// Releases the native reference if it has not been released yet.
  /// Safe to call more than once.
  void dispose() {
    if (!isReleased) release();
  }

  /// Whether this handle is still usable.
  bool get isAlive => !isReleased;
}
