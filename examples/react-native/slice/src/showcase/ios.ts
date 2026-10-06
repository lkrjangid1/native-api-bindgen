/**
 * Real iOS tasks built only from generated bindings (TypeScript -> JSI ->
 * Objective-C++): UIDevice, NSProcessInfo, NSFileManager, UIPasteboard,
 * NSUserDefaults, haptics, the share sheet, UIApplication and
 * AVSpeechSynthesizer. UIKit calls are dispatched to the main thread by the
 * runtime. No hand-written TurboModule, no Objective-C/Swift.
 */
import {
  AVSpeechBoundary,
  AVSpeechSynthesisVoice,
  AVSpeechSynthesizer,
  AVSpeechUtterance,
  NSArray,
  NSDictionary,
  NSFileManager,
  NSNumber,
  NSProcessInfo,
  NSProcessInfoThermalState,
  NSSearchPathDirectory,
  NSSearchPathDomainMask,
  NSURL,
  NSUserDefaults,
  UIActivityViewController,
  UIApplication,
  UIDevice,
  UIDeviceBatteryState,
  UIImpactFeedbackGenerator,
  UIImpactFeedbackStyle,
  UINotificationFeedbackGenerator,
  UINotificationFeedbackType,
  UIPasteboard,
  UIViewController,
  UIWindow,
  UIWindowScene,
  nsArrayItems,
  nsString,
} from '../../native-api-bindings/ios';

export type IosStatus = {
  device: string;
  system: string;
  batteryLevel: number | null;
  batteryState: string;
  thermalState: string;
  lowPowerMode: boolean;
  physicalMemoryBytes: number;
  processors: number;
  uptimeSeconds: number;
  freeStorageBytes: number | null;
  totalStorageBytes: number | null;
};

/** Battery, thermal state, memory, CPUs, uptime and free storage. */
export function deviceStatus(): IosStatus {
  const device = UIDevice.currentDevice;
  device.batteryMonitoringEnabled = true;
  const info = NSProcessInfo.processInfo;
  const level = device.batteryLevel; // -1 when unknown (simulator)
  const storage = storageStatus();
  return {
    device: `${device.name} · ${device.model}`,
    system: `${device.systemName} ${device.systemVersion}`,
    batteryLevel: level < 0 ? null : level,
    batteryState:
      {
        [String(UIDeviceBatteryState.UIDeviceBatteryStateCharging)]: 'charging',
        [String(UIDeviceBatteryState.UIDeviceBatteryStateFull)]: 'full',
        [String(UIDeviceBatteryState.UIDeviceBatteryStateUnplugged)]:
          'on battery',
      }[String(device.batteryState)] ?? 'unknown',
    thermalState:
      {
        [String(NSProcessInfoThermalState.NSProcessInfoThermalStateNominal)]:
          'nominal',
        [String(NSProcessInfoThermalState.NSProcessInfoThermalStateFair)]:
          'fair',
        [String(NSProcessInfoThermalState.NSProcessInfoThermalStateSerious)]:
          'serious',
      }[String(info.thermalState)] ?? 'critical',
    lowPowerMode: info.lowPowerModeEnabled,
    physicalMemoryBytes: Number(info.physicalMemory),
    processors: Number(info.activeProcessorCount),
    uptimeSeconds: info.systemUptime,
    freeStorageBytes: storage?.free ?? null,
    totalStorageBytes: storage?.total ?? null,
  };
}

/** -[NSFileManager attributesOfFileSystemForPath:error:] on Documents. */
function storageStatus(): { free: number; total: number } | null {
  const fm = NSFileManager.defaultManager;
  const docs = nsArrayItems(
    fm.URLsForDirectory(
      NSSearchPathDirectory.NSDocumentDirectory,
      NSSearchPathDomainMask.NSUserDomainMask,
    ),
  );
  if (docs.length === 0) return null;
  const path = docs[0].as(NSURL).path;
  if (path === null) return null;
  const attrs = fm.attributesOfFileSystemForPath(path);
  if (attrs === null) return null;
  const values: Record<string, number> = {};
  const keys = nsArrayItems(attrs.allKeys);
  const vals = nsArrayItems(attrs.allValues);
  keys.forEach((k, i) => {
    if (NSNumber.isA(vals[i])) {
      values[k.toString()] = Number(vals[i].as(NSNumber).longLongValue);
    }
  });
  const free = values.NSFileSystemFreeSize;
  const total = values.NSFileSystemSize;
  return free === undefined || total === undefined ? null : { free, total };
}

/** UIPasteboard.generalPasteboard.string = text. */
export function copy(text: string): void {
  UIPasteboard.generalPasteboard.string_ = text;
}

/** The pasteboard's string, or null. */
export function paste(): string | null {
  return UIPasteboard.generalPasteboard.string_;
}

/** Saves [note] in NSUserDefaults; it survives restarts. */
export function saveNote(note: string): void {
  // setObject:forKey: is typed `id`: nsString() makes the NSString object.
  NSUserDefaults.standardUserDefaults.setObject(
    nsString(note),
    'showcase.note',
  );
}

/** The saved note, or null. */
export function loadNote(): string | null {
  return NSUserDefaults.standardUserDefaults.stringForKey('showcase.note');
}

/** A medium impact, then a success notification. */
export async function haptics(): Promise<void> {
  UIImpactFeedbackGenerator.alloc()
    .initWithStyle(UIImpactFeedbackStyle.UIImpactFeedbackStyleMedium)
    .impactOccurred();
  await new Promise<void>(r => setTimeout(r, 150));
  UINotificationFeedbackGenerator.new$().notificationOccurred(
    UINotificationFeedbackType.UINotificationFeedbackTypeSuccess,
  );
}

/** The key window's root view controller, via the connected window scenes. */
function rootViewController(): UIViewController | null {
  for (const scene of nsArrayItems(
    UIApplication.sharedApplication.connectedScenes.allObjects,
  )) {
    if (!UIWindowScene.isA(scene)) continue;
    for (const w of nsArrayItems(scene.as(UIWindowScene).windows)) {
      const window = w.as(UIWindow);
      if (window.keyWindow) return window.rootViewController;
    }
  }
  return null;
}

/** Presents UIActivityViewController with [text]. */
export async function share(text: string): Promise<void> {
  const root = rootViewController();
  if (root === null) throw new Error('No key window');
  const sheet = UIActivityViewController.alloc().initWithActivityItems(
    NSArray.arrayWithObject(nsString(text)),
    null,
  );
  const popover = sheet.popoverPresentationController; // iPad
  if (popover !== null) popover.sourceView = root.view;
  await root.presentViewControllerAsync(sheet, true, null);
}

/**
 * Opens this app's page in Settings, where its permissions (including
 * location) are shown. iOS has no public URL for the system Location Services
 * page. Global string constants are not generated yet, so this uses the value
 * of UIApplicationOpenSettingsURLString.
 */
export function openAppSettings(): Promise<boolean> {
  return openUrl('app-settings:');
}

/** -[UIApplication openURL:options:completionHandler:]; the block is a JS function. */
export function openUrl(url: string): Promise<boolean> {
  const nsUrl = NSURL.URLWithString(url);
  if (nsUrl === null) throw new Error(`Invalid URL ${url}`);
  return new Promise(resolve =>
    UIApplication.sharedApplication.openURL$options$completionHandler(
      nsUrl,
      NSDictionary.dictionary(),
      resolve,
    ),
  );
}

let synth: AVSpeechSynthesizer | null = null;

/** Speaks [text] with AVSpeechSynthesizer in the device language. */
export function speak(text: string): void {
  synth ??= AVSpeechSynthesizer.new$();
  synth.stopSpeakingAtBoundary(AVSpeechBoundary.AVSpeechBoundaryImmediate);
  const utterance = AVSpeechUtterance.speechUtteranceWithString(text);
  utterance.voice = AVSpeechSynthesisVoice.voiceWithLanguage(
    AVSpeechSynthesisVoice.currentLanguageCode(),
  );
  synth.speakUtterance(utterance);
}

/** Whether speech is in progress. */
export function speaking(): boolean {
  return synth?.speaking ?? false;
}
