/**
 * Real Android tasks built only from generated bindings (TypeScript -> JSI ->
 * JNI): system services, a sticky broadcast, intents, the clipboard,
 * SharedPreferences, the vibrator and text-to-speech. No hand-written
 * TurboModule, no Java/Kotlin.
 */
import {
  ActivityManager,
  ActivityManager_MemoryInfo,
  AndroidApi,
  BatteryManager,
  Build,
  ClipData,
  ConnectivityManager,
  Context,
  Environment,
  Intent,
  IntentFilter,
  Settings,
  Locale,
  NativeApiUnavailableError,
  NetworkCapabilities,
  StatFs,
  TextToSpeech,
  TextToSpeech_OnInitListener,
  Uri,
  VibrationEffect,
  Vibrator,
  android_content_ClipboardManager as ClipboardManager,
  applicationContext,
  currentActivity,
  type JavaClass,
  type JavaObject,
} from '../../native-api-bindings';

export type AndroidStatus = {
  device: string;
  apiLevel: number;
  batteryPercent: number | null;
  charging: boolean;
  availMemBytes: number;
  totalMemBytes: number;
  lowMemory: boolean;
  freeStorageBytes: number;
  totalStorageBytes: number;
  network: string;
};

function service<T extends JavaObject>(name: string, cls: JavaClass<T>): T {
  return applicationContext().getSystemService(name)!.as(cls);
}

/** Battery (sticky ACTION_BATTERY_CHANGED), memory, storage and network. */
export function deviceStatus(): AndroidStatus {
  const ctx = applicationContext();
  const battery = ctx.registerReceiver(
    null,
    IntentFilter.new$String(Intent.ACTION_BATTERY_CHANGED),
  );
  let batteryPercent: number | null = null;
  let charging = false;
  if (battery !== null) {
    const level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
    const scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
    if (level >= 0 && scale > 0)
      batteryPercent = Math.floor((level * 100) / scale);
    const status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
    charging =
      status === BatteryManager.BATTERY_STATUS_CHARGING ||
      status === BatteryManager.BATTERY_STATUS_FULL;
  }

  const am = service(Context.ACTIVITY_SERVICE, ActivityManager);
  const mem = ActivityManager_MemoryInfo.new();
  am.getMemoryInfo(mem);

  const fs = StatFs.new(Environment.getDataDirectory()!.getAbsolutePath());
  return {
    device: `${Build.MANUFACTURER} ${Build.MODEL}`,
    apiLevel: AndroidApi.sdkInt,
    batteryPercent,
    charging,
    availMemBytes: Number(mem.availMem),
    totalMemBytes: Number(mem.totalMem),
    lowMemory: mem.lowMemory,
    freeStorageBytes: Number(fs.getAvailableBytes()),
    totalStorageBytes: Number(fs.getTotalBytes()),
    network: network(),
  };
}

function network(): string {
  const cm = service(Context.CONNECTIVITY_SERVICE, ConnectivityManager);
  const active = cm.getActiveNetwork();
  if (active === null) return 'offline';
  const caps = cm.getNetworkCapabilities(active);
  if (caps === null) return 'unknown';
  const kind = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    ? 'Wi-Fi'
    : caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)
    ? 'cellular'
    : caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    ? 'ethernet'
    : 'other';
  const mbps = caps.getLinkDownstreamBandwidthKbps() / 1000;
  return `${kind} · ${mbps.toFixed(1)} Mbps down`;
}

function activity() {
  const a = currentActivity();
  if (a === null) throw new Error('No foreground Activity');
  return a;
}

/** ACTION_SEND through the system chooser. */
export function share(text: string): void {
  const send = Intent.new$String(Intent.ACTION_SEND)
    .setType('text/plain')
    .putExtra$String$String(Intent.EXTRA_TEXT, text);
  activity().startActivity(Intent.createChooser(send, 'Share via')!);
}

/** Opens [url] in the browser (ACTION_VIEW). */
export function openUrl(url: string): void {
  activity().startActivity(
    Intent.new$String$Uri(Intent.ACTION_VIEW, Uri.parse(url)),
  );
}

/** Opens the system Location settings page (ACTION_LOCATION_SOURCE_SETTINGS). */
export function openLocationSettings(): void {
  activity().startActivity(
    Intent.new$String(Settings.ACTION_LOCATION_SOURCE_SETTINGS),
  );
}

/**
 * Opens this app's settings page, where its permissions (including location)
 * are granted or revoked (ACTION_APPLICATION_DETAILS_SETTINGS + package: URI).
 */
export function openAppPermissions(): void {
  const pkg = applicationContext().getPackageName();
  activity().startActivity(
    Intent.new$String$Uri(
      Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
      Uri.parse(`package:${pkg}`),
    ),
  );
}

/** ClipboardManager.setPrimaryClip(ClipData.newPlainText(...)). */
export function copy(text: string): void {
  service(Context.CLIPBOARD_SERVICE, ClipboardManager).setPrimaryClip(
    ClipData.newPlainText('native-api-bindgen', text)!,
  );
}

/** The clipboard's first item as text, or null. */
export function paste(): string | null {
  const clip = service(
    Context.CLIPBOARD_SERVICE,
    ClipboardManager,
  ).getPrimaryClip();
  if (clip === null || clip.getItemCount() === 0) return null;
  return (
    clip.getItemAt(0)?.coerceToText(applicationContext())?.toString() ?? null
  );
}

function prefs() {
  return applicationContext().getSharedPreferences(
    'showcase',
    Context.MODE_PRIVATE,
  )!;
}

/** Saves [note] in SharedPreferences; it survives restarts. */
export function saveNote(note: string): void {
  prefs().edit()!.putString('note', note)!.apply();
}

/** The saved note, or null. */
export function loadNote(): string | null {
  return prefs().getString('note', null);
}

/**
 * A 60 ms vibration. VibrationEffect is API 26+, newer than the app's minApi
 * (24): the generated call is guarded and throws NativeApiUnavailableError on
 * older devices, where we fall back to the legacy vibrate(long).
 */
export function vibrate(): string {
  const vibrator = service(Context.VIBRATOR_SERVICE, Vibrator);
  if (!vibrator.hasVibrator()) return 'no vibrator on this device';
  try {
    vibrator.vibrate$VibrationEffect(
      VibrationEffect.createOneShot(60n, VibrationEffect.DEFAULT_AMPLITUDE),
    );
    return 'VibrationEffect.createOneShot (API 26+)';
  } catch (e) {
    if (!(e instanceof NativeApiUnavailableError)) throw e;
    vibrator.vibrate(60n);
    return 'legacy vibrate(long)';
  }
}

let tts: Promise<TextToSpeech> | null = null;

/**
 * Text-to-speech. The engine reports readiness through
 * TextToSpeech.OnInitListener, implemented in JavaScript.
 */
export async function speak(text: string): Promise<void> {
  tts ??= new Promise<TextToSpeech>((resolve, reject) => {
    const engine: TextToSpeech = TextToSpeech.new(
      applicationContext(),
      TextToSpeech_OnInitListener.implement(
        {
          onInit: status => {
            if (status !== TextToSpeech.SUCCESS) {
              reject(new Error(`TextToSpeech init failed (${status})`));
              return;
            }
            engine.setLanguage(Locale.getDefault());
            resolve(engine);
          },
        },
        { async: ['onInit'] },
      ),
    );
  });
  const engine = await tts;
  const r = engine.speak$CharSequence$int$Bundle$String(
    text,
    TextToSpeech.QUEUE_FLUSH,
    null,
    'showcase',
  );
  if (r !== TextToSpeech.SUCCESS) throw new Error(`speak() returned ${r}`);
}
