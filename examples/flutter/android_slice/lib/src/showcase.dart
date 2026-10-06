import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart' as jf;
import 'package:native_api_runtime/native_api_runtime.dart';

import 'generated/bindings.dart';

/// A snapshot of device state, read through generated Android bindings.
typedef DeviceStatus = ({
  String device,
  int? apiLevel,
  int? batteryPercent,
  bool charging,
  int availMemBytes,
  int totalMemBytes,
  bool lowMemory,
  int freeStorageBytes,
  int totalStorageBytes,
  String network,
});

/// Real tasks built only from generated bindings: system services, sticky
/// broadcasts, intents, the clipboard, SharedPreferences, the vibrator and
/// text-to-speech. No MethodChannel, no hand-written Kotlin.
abstract final class Showcase {
  static Context get _ctx => jf.androidApplicationContext.as(Context.type);

  static Activity _activity() {
    final engineId = PlatformDispatcher.instance.engineId;
    final activity = engineId == null
        ? null
        : jf.androidActivity(engineId)?.as(Activity.type);
    if (activity == null) throw StateError('No foreground Activity');
    return activity;
  }

  static T _service<T extends JObject>(JType<T> type, String name) =>
      _ctx.getSystemService(name.toJString())!.as(type);

  // ---- Device dashboard ---------------------------------------------------

  /// Battery (sticky `ACTION_BATTERY_CHANGED`), memory (`ActivityManager`),
  /// storage (`StatFs`) and the active network (`ConnectivityManager`).
  static DeviceStatus deviceStatus() {
    final battery = _ctx.registerReceiver(
      null,
      IntentFilter.new$String(Intent.ACTION_BATTERY_CHANGED.toJString()),
    );
    int? percent;
    var charging = false;
    if (battery != null) {
      final level = battery.getIntExtra(
        BatteryManager.EXTRA_LEVEL.toJString(),
        -1,
      );
      final scale = battery.getIntExtra(
        BatteryManager.EXTRA_SCALE.toJString(),
        -1,
      );
      if (level >= 0 && scale > 0) percent = level * 100 ~/ scale;
      final status = battery.getIntExtra(
        BatteryManager.EXTRA_STATUS.toJString(),
        -1,
      );
      charging =
          status == BatteryManager.BATTERY_STATUS_CHARGING ||
          status == BatteryManager.BATTERY_STATUS_FULL;
      battery.release();
    }

    final am = _service(ActivityManager.type, Context.ACTIVITY_SERVICE);
    final mem = ActivityManager_MemoryInfo();
    am.getMemoryInfo(mem);

    final dataDir = Environment.getDataDirectory()!;
    final fs = StatFs(dataDir.getAbsolutePath());

    final status = (
      device:
          '${Build.MANUFACTURER?.toDartString()} ${Build.MODEL?.toDartString()}',
      apiLevel: AndroidApi.sdkInt,
      batteryPercent: percent,
      charging: charging,
      availMemBytes: mem.availMem,
      totalMemBytes: mem.totalMem,
      lowMemory: mem.lowMemory,
      freeStorageBytes: fs.getAvailableBytes(),
      totalStorageBytes: fs.getTotalBytes(),
      network: _network(),
    );
    for (final o in [mem, am, fs, dataDir]) {
      o.release();
    }
    return status;
  }

  static String _network() {
    final cm = _service(ConnectivityManager.type, Context.CONNECTIVITY_SERVICE);
    final network = cm.getActiveNetwork();
    if (network == null) return 'offline';
    final caps = cm.getNetworkCapabilities(network);
    if (caps == null) return 'unknown';
    final kind = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
        ? 'Wi-Fi'
        : caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
        ? 'cellular'
        : caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
        ? 'ethernet'
        : 'other';
    final down = caps.getLinkDownstreamBandwidthKbps();
    caps.release();
    network.release();
    return '$kind · ${(down / 1000).toStringAsFixed(1)} Mbps down';
  }

  // ---- Share sheet ----------------------------------------------------------

  /// `ACTION_SEND` text through the system chooser.
  static void share(String text) {
    final send = Intent.new$String(Intent.ACTION_SEND.toJString())
      ..setType('text/plain'.toJString())
      ..putExtra$String$String(Intent.EXTRA_TEXT.toJString(), text.toJString());
    final chooser = Intent.createChooser(send, 'Share via'.toJString())!;
    final activity = _activity();
    try {
      activity.startActivity(chooser);
    } finally {
      for (final o in [chooser, send, activity]) {
        o.release();
      }
    }
  }

  /// Opens [url] in the default browser (`ACTION_VIEW`).
  static void openUrl(String url) {
    final intent = Intent.new$String$Uri(
      Intent.ACTION_VIEW.toJString(),
      Uri.parse(url.toJString()),
    );
    final activity = _activity();
    try {
      activity.startActivity(intent);
    } finally {
      intent.release();
      activity.release();
    }
  }

  /// Opens the system Location settings page
  /// (`Settings.ACTION_LOCATION_SOURCE_SETTINGS`).
  static void openLocationSettings() => _start(
    Intent.new$String(Settings.ACTION_LOCATION_SOURCE_SETTINGS.toJString()),
  );

  /// Opens this app's settings page, where its permissions (including
  /// location) are granted or revoked
  /// (`Settings.ACTION_APPLICATION_DETAILS_SETTINGS` + `package:` URI).
  static void openAppPermissions() => _start(
    Intent.new$String$Uri(
      Settings.ACTION_APPLICATION_DETAILS_SETTINGS.toJString(),
      Uri.parse('package:${_ctx.getPackageName()!.toDartString()}'.toJString()),
    ),
  );

  static void _start(Intent intent) {
    final activity = _activity();
    try {
      activity.startActivity(intent);
    } finally {
      intent.release();
      activity.release();
    }
  }

  // ---- Clipboard ------------------------------------------------------------

  /// `ClipboardManager.setPrimaryClip(ClipData.newPlainText(...))`.
  static void copy(String text) {
    final cm = _service(ClipboardManager.type, Context.CLIPBOARD_SERVICE);
    cm.setPrimaryClip(
      ClipData.newPlainText(
        'native-api-bindgen'.toJString(),
        text.toJString(),
      )!,
    );
    cm.release();
  }

  /// The clipboard's first item as text, or null when it is empty.
  static String? paste() {
    final cm = _service(ClipboardManager.type, Context.CLIPBOARD_SERVICE);
    final clip = cm.getPrimaryClip();
    cm.release();
    if (clip == null || clip.getItemCount() == 0) return null;
    final text = clip.getItemAt(0)?.coerceToText(_ctx)?.toString();
    clip.release();
    return text;
  }

  // ---- Persistent note (SharedPreferences) ----------------------------------

  static SharedPreferences _prefs() =>
      _ctx.getSharedPreferences('showcase'.toJString(), Context.MODE_PRIVATE)!;

  /// Saves [note]; it survives app restarts.
  static void saveNote(String note) {
    final prefs = _prefs();
    prefs.edit()!.putString('note'.toJString(), note.toJString())!.apply();
    prefs.release();
  }

  /// The saved note, or null.
  static String? loadNote() {
    final prefs = _prefs();
    final note = prefs
        .getString('note'.toJString(), null)
        ?.toDartString(releaseOriginal: true);
    prefs.release();
    return note;
  }

  // ---- Haptics ---------------------------------------------------------------

  /// A 60 ms vibration. `VibrationEffect` is API 26+, newer than this app's
  /// `minApi` (24), so the generated call is guarded: on older devices it
  /// throws [NativeApiUnavailableException] and we fall back to the legacy
  /// `vibrate(long)`.
  static String vibrate() {
    final vibrator = _service(Vibrator.type, Context.VIBRATOR_SERVICE);
    try {
      if (!vibrator.hasVibrator()) return 'no vibrator on this device';
      try {
        final effect = VibrationEffect.createOneShot(
          60,
          VibrationEffect.DEFAULT_AMPLITUDE,
        );
        vibrator.vibrate$VibrationEffect(effect);
        return 'VibrationEffect.createOneShot (API 26+)';
      } on NativeApiUnavailableException {
        vibrator.vibrate(60);
        return 'legacy vibrate(long)';
      }
    } finally {
      vibrator.release();
    }
  }

  /// A native `Toast`.
  static void toast(String text) {
    Toast.makeText$Context$CharSequence$int(
      _ctx,
      text.toJString(),
      Toast.LENGTH_SHORT,
    )!.show();
  }
}

/// Android text-to-speech: the engine reports readiness through
/// `TextToSpeech.OnInitListener`, implemented here in Dart.
final class Speaker {
  Speaker._(this._ready);

  final Future<TextToSpeech> _ready;

  static Speaker? _instance;

  /// The shared speaker (created on first use).
  static Speaker get instance => _instance ??= Speaker._(_create());

  static Future<TextToSpeech> _create() {
    final ready = Completer<int>();
    final tts = TextToSpeech(
      jf.androidApplicationContext.as(Context.type),
      TextToSpeech_OnInitListener.implement(
        $TextToSpeech_OnInitListener(
          onInit: ready.complete,
          onInit$async: true,
        ),
      ),
    );
    return ready.future.timeout(const Duration(seconds: 10)).then((status) {
      if (status != TextToSpeech.SUCCESS) {
        throw StateError('TextToSpeech init failed ($status)');
      }
      tts.setLanguage(Locale.getDefault());
      return tts;
    });
  }

  /// Speaks [text], interrupting anything in progress.
  Future<void> speak(String text) async {
    final tts = await _ready;
    final r = tts.speak$CharSequence$int$Bundle$String(
      text.toJString(),
      TextToSpeech.QUEUE_FLUSH,
      null,
      'showcase'.toJString(),
    );
    if (r != TextToSpeech.SUCCESS) throw StateError('speak() returned $r');
  }
}
