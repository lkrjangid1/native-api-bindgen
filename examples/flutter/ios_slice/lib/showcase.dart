import 'dart:async';

import 'package:objective_c/objective_c.dart' as objc;

import 'src/generated/apple.dart' as ios;

/// A snapshot of device state, read through generated UIKit / Foundation
/// bindings.
typedef DeviceStatus = ({
  String device,
  String system,
  double? batteryLevel,
  String batteryState,
  String thermalState,
  bool lowPowerMode,
  int physicalMemoryBytes,
  int processors,
  Duration uptime,
  int? freeStorageBytes,
  int? totalStorageBytes,
});

/// Real tasks built only from generated bindings: UIDevice, NSProcessInfo,
/// NSFileManager, UIPasteboard, NSUserDefaults, haptics, the share sheet,
/// UIApplication and AVSpeechSynthesizer. No platform channel, no plugin.
abstract final class Showcase {
  // ---- Device dashboard ---------------------------------------------------

  /// Battery, thermal state, memory, CPUs, uptime and free storage.
  static DeviceStatus deviceStatus() {
    final device = ios.UIDevice.currentDevice..batteryMonitoringEnabled = true;
    final info = ios.NSProcessInfo.processInfo;
    final level = device.batteryLevel; // -1 when unknown (simulator)
    final storage = _storage();
    return (
      device: '${device.name.toDartString()} · ${device.model.toDartString()}',
      system:
          '${device.systemName.toDartString()} ${device.systemVersion.toDartString()}',
      batteryLevel: level < 0 ? null : level,
      batteryState: switch (device.batteryState) {
        ios.UIDeviceBatteryState.UIDeviceBatteryStateCharging => 'charging',
        ios.UIDeviceBatteryState.UIDeviceBatteryStateFull => 'full',
        ios.UIDeviceBatteryState.UIDeviceBatteryStateUnplugged => 'on battery',
        _ => 'unknown',
      },
      thermalState: switch (info.thermalState) {
        ios.NSProcessInfoThermalState.NSProcessInfoThermalStateNominal =>
          'nominal',
        ios.NSProcessInfoThermalState.NSProcessInfoThermalStateFair => 'fair',
        ios.NSProcessInfoThermalState.NSProcessInfoThermalStateSerious =>
          'serious',
        _ => 'critical',
      },
      lowPowerMode: info.lowPowerModeEnabled,
      physicalMemoryBytes: info.physicalMemory,
      processors: info.activeProcessorCount,
      uptime: Duration(milliseconds: (info.systemUptime * 1000).round()),
      freeStorageBytes: storage?.free,
      totalStorageBytes: storage?.total,
    );
  }

  /// `-[NSFileManager attributesOfFileSystemForPath:error:]` on the app's
  /// Documents volume.
  static ({int free, int total})? _storage() {
    final fm = ios.NSFileManager.defaultManager;
    final docs = fm.URLsForDirectory(
      ios.NSSearchPathDirectory.NSDocumentDirectory,
      inDomains: ios.NSSearchPathDomainMask.NSUserDomainMask,
    );
    if (docs.count == 0) return null;
    final path = objc.NSURL.as(docs.objectAtIndex(0)).path;
    if (path == null) return null;
    final attrs = fm.attributesOfFileSystemForPath(path);
    if (attrs == null) return null;
    int? number(String key) {
      final v = attrs.objectForKey(key.toNSString());
      return v == null ? null : objc.NSNumber.as(v).longLongValue;
    }

    final free = number('NSFileSystemFreeSize');
    final total = number('NSFileSystemSize');
    return free == null || total == null ? null : (free: free, total: total);
  }

  // ---- Clipboard ------------------------------------------------------------

  /// `UIPasteboard.generalPasteboard.string = text`.
  static void copy(String text) =>
      ios.UIPasteboard.generalPasteboard.string = text.toNSString();

  /// The pasteboard's string, or null.
  static String? paste() =>
      ios.UIPasteboard.generalPasteboard.string?.toDartString();

  // ---- Persistent note (NSUserDefaults) -------------------------------------

  /// Saves [note]; it survives app restarts.
  static void saveNote(String note) => ios.NSUserDefaults.standardUserDefaults
      .setObject(note.toNSString(), forKey: 'showcase.note'.toNSString());

  /// The saved note, or null.
  static String? loadNote() => ios.NSUserDefaults.standardUserDefaults
      .stringForKey('showcase.note'.toNSString())
      ?.toDartString();

  // ---- Haptics ---------------------------------------------------------------

  /// A medium impact, then a success notification
  /// (`UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`).
  static Future<void> haptics() async {
    ios.UIImpactFeedbackGenerator.alloc()
        .initWithStyle(ios.UIImpactFeedbackStyle.UIImpactFeedbackStyleMedium)
        .impactOccurred();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    ios.UINotificationFeedbackGenerator.new$().notificationOccurred(
      ios.UINotificationFeedbackType.UINotificationFeedbackTypeSuccess,
    );
  }

  // ---- Share sheet and URLs ---------------------------------------------------

  /// The key window's root view controller, found through the connected
  /// `UIWindowScene`s.
  static ios.UIViewController? _rootViewController() {
    final scenes =
        ios.UIApplication.sharedApplication.connectedScenes.allObjects;
    for (var i = 0; i < scenes.count; i++) {
      final scene = scenes.objectAtIndex(i);
      if (!ios.UIWindowScene.isA(scene)) continue;
      final windows = ios.UIWindowScene.as(scene).windows;
      for (var j = 0; j < windows.count; j++) {
        final window = ios.UIWindow.as(windows.objectAtIndex(j));
        if (window.keyWindow) return window.rootViewController;
      }
    }
    return null;
  }

  /// Presents `UIActivityViewController` with [text]; completes when the
  /// sheet is on screen.
  static Future<void> share(String text) {
    final root = _rootViewController();
    if (root == null) throw StateError('No key window');
    final sheet = ios.UIActivityViewController.alloc().initWithActivityItems(
      objc.NSArray.of([text.toNSString()]),
    );
    // iPad presents the sheet as a popover anchored to a view.
    sheet.popoverPresentationController?.sourceView = root.view;
    return root.presentViewControllerAsync(sheet, animated: true);
  }

  /// Opens this app's page in Settings, where its permissions (including
  /// location) are shown. iOS has no public URL for the system Location
  /// Services page. Global string constants are not generated yet, so this
  /// uses the value of `UIApplicationOpenSettingsURLString`.
  static Future<bool> openAppSettings() => openUrl('app-settings:');

  /// `-[UIApplication openURL:options:completionHandler:]`; the completion
  /// block becomes a Dart callback.
  static Future<bool> openUrl(String url) {
    final nsUrl = objc.NSURL.URLWithString(url.toNSString());
    if (nsUrl == null) throw ArgumentError.value(url, 'url');
    final opened = Completer<bool>();
    ios.UIApplication.sharedApplication.openURL$options$completionHandler(
      nsUrl,
      options: objc.NSDictionary.dictionary(),
      completionHandler: opened.complete,
    );
    return opened.future;
  }
}

/// Text-to-speech with `AVSpeechSynthesizer` (AVFAudio).
final class Speaker {
  Speaker._();

  /// The shared speaker; it keeps the synthesizer alive while speaking.
  static final instance = Speaker._();

  final _synth = ios.AVSpeechSynthesizer.new$();

  /// Whether speech is in progress.
  bool get speaking => _synth.speaking;

  /// Speaks [text] in the device language, interrupting anything in progress.
  void speak(String text) {
    _synth.stopSpeakingAtBoundary(
      ios.AVSpeechBoundary.AVSpeechBoundaryImmediate,
    );
    final utterance =
        ios.AVSpeechUtterance.speechUtteranceWithString(text.toNSString())
          ..voice = ios.AVSpeechSynthesisVoice.voiceWithLanguage(
            ios.AVSpeechSynthesisVoice.currentLanguageCode(),
          );
    _synth.speakUtterance(utterance);
  }
}
