import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart' as jf;
import 'package:native_api_runtime/native_api_runtime.dart';

import 'generated/bindings.dart';

/// Small, readable demonstrations of the generated bindings. Every Android
/// call below goes through code generated from android.jar — there is no
/// MethodChannel and no hand-written Java/Kotlin.
abstract final class Slice {
  /// The application `Context`, typed with the generated binding.
  static Context get appContext => jf.androidApplicationContext.as(Context.type);

  /// `Context#getPackageName()`.
  static String packageName() => appContext.getPackageName()!.toDartString(releaseOriginal: true);

  /// Builds `new Intent(Intent.ACTION_VIEW, Uri.parse(url))` and reads it back.
  static ({String action, String data}) viewIntent(String url) {
    final uri = Uri.parse(url.toJString())!;
    final intent = Intent.new$String$Uri(Intent.ACTION_VIEW.toJString(), uri);
    try {
      return (
        action: intent.getAction()!.toDartString(releaseOriginal: true),
        data: intent.getData()!.toString(),
      );
    } finally {
      intent.release();
      uri.release();
    }
  }

  /// `Bundle#putString` / `getString` including a missing key (null).
  static (String?, String?) bundleRoundTrip() {
    final b = Bundle();
    b.putString('greeting'.toJString(), 'hello from Dart'.toJString());
    final present = b.getString('greeting'.toJString())?.toDartString(releaseOriginal: true);
    final missing = b.getString('absent'.toJString())?.toDartString(releaseOriginal: true);
    b.release();
    return (present, missing);
  }

  /// Posts a `Runnable` implemented in Dart to the main `Looper` via
  /// `Handler#post` and completes when Java runs it.
  static Future<String> postToMainLooper() {
    final done = Completer<String>();
    final handler = Handler.new$Looper(Looper.getMainLooper()!);
    late final Runnable task;
    task = Runnable.implement($Runnable(
      run: () {
        final onMain = Looper.myLooper() == Looper.getMainLooper();
        done.complete('Runnable ran (main looper: $onMain)');
      },
      run$async: true,
    ));
    handler.post(task);
    return done.future;
  }

  /// Uses the current `Activity` synchronously (see jni_flutter docs).
  static String? activityClassName() {
    final engineId = PlatformDispatcher.instance.engineId;
    if (engineId == null) return null;
    final activity = jf.androidActivity(engineId)?.as(Activity.type);
    if (activity == null) return null;
    try {
      return activity.getLocalClassName().toDartString(releaseOriginal: true);
    } finally {
      activity.release();
    }
  }

  /// Starts an ACTION_VIEW activity for [url] (opens the browser).
  static void openUrl(String url) {
    final engineId = PlatformDispatcher.instance.engineId;
    final activity = engineId == null ? null : jf.androidActivity(engineId)?.as(Activity.type);
    if (activity == null) throw StateError('No foreground Activity');
    final intent = Intent.new$String$Uri(Intent.ACTION_VIEW.toJString(), Uri.parse(url.toJString()));
    try {
      activity.startActivity(intent);
    } finally {
      intent.release();
      activity.release();
    }
  }

  /// Running device API level from the runtime (`Build.VERSION.SDK_INT`).
  static int? sdkInt() => AndroidApi.sdkInt;
}
