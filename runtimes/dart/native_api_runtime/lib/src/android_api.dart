import 'dart:io' show Platform;

import 'package:jni/jni.dart';

import 'errors.dart';

/// Platform version checks for generated Android bindings (TRD §64).
abstract final class AndroidApi {
  static int? _sdkInt;
  static int? _sdkIntFull;

  /// Test hook: overrides the detected version (`major * 100000 + minor`).
  /// Set to null to restore detection.
  static int? debugOverrideFullVersion;

  /// `Build.VERSION.SDK_INT` of the running device, or null when not running
  /// on Android (e.g. host-JVM tests), where guards are not enforced.
  static int? get sdkInt {
    final o = debugOverrideFullVersion;
    if (o != null) return o ~/ 100000;
    if (!Platform.isAndroid) return null;
    return _sdkInt ??= _readStaticInt('SDK_INT');
  }

  /// `major * 100000 + minor`, matching `Build.VERSION.SDK_INT_FULL`
  /// (available from API 36; derived from `SDK_INT` on older devices).
  static int? get fullVersion {
    final o = debugOverrideFullVersion;
    if (o != null) return o;
    final major = sdkInt;
    if (major == null) return null;
    if (major < 36) return major * 100000;
    return _sdkIntFull ??= _readStaticInt('SDK_INT_FULL');
  }

  /// Whether the device runs at least API [major].[minor]. Returns true when
  /// not running on Android.
  static bool isAtLeast(int major, [int minor = 0]) {
    final v = fullVersion;
    return v == null || v >= major * 100000 + minor;
  }

  /// Throws [NativeApiUnavailableException] unless [isAtLeast].
  static void require(int major, int minor, String symbol) {
    if (isAtLeast(major, minor)) return;
    final v = fullVersion!;
    final actual = v % 100000 == 0
        ? '${v ~/ 100000}'
        : '${v ~/ 100000}.${v % 100000}';
    throw NativeApiUnavailableException(
      symbol,
      minor == 0 ? '$major' : '$major.$minor',
      actual,
    );
  }

  static int _readStaticInt(String field) {
    final cls = JClass.forName(r'android/os/Build$VERSION');
    try {
      return cls.staticFieldId(field, 'I').get(cls, jint.type);
    } finally {
      cls.release();
    }
  }
}
