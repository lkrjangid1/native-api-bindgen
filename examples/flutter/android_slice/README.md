# Flutter on Android: native tasks from Dart

Every native call in this app goes through Dart bindings that `native-api-bindgen` generated from `android.jar`, over `package:jni`. There is no MethodChannel, no plugin per API and no hand-written Kotlin.

| Task | Android APIs |
|---|---|
| Live device dashboard (refreshes every 3 s) | sticky `ACTION_BATTERY_CHANGED` broadcast + `BatteryManager`, `ActivityManager.MemoryInfo`, `StatFs` + `Environment`, `ConnectivityManager` + `NetworkCapabilities`, `Build` |
| Speak text | `TextToSpeech`, with `TextToSpeech.OnInitListener` implemented in Dart |
| Share text | `Intent.ACTION_SEND` + `Intent.createChooser` |
| Copy, then paste back | `ClipboardManager` + `ClipData` |
| Note that survives restarts | `SharedPreferences.Editor` |
| Vibrate | `Vibrator` + `VibrationEffect`: API 26+, newer than `minApi: 24`, so the call is guarded at runtime, with a fallback |
| Location settings | `Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)`; the app's permission page via `Settings.ACTION_APPLICATION_DETAILS_SETTINGS` + `package:` URI |
| Toast, open a URL | `Toast.makeText`, `Intent.ACTION_VIEW` + `Activity.startActivity` |

Code: `lib/src/showcase.dart` (tasks) and `lib/main.dart` (UI). The selected classes are listed in `native_api_bindgen.yaml`.

```sh
# from the repository root
fixtures/kotlin/basic/gradlew -p fixtures/kotlin/basic jar          # Kotlin library used by the tests
dart run native_api_bindgen --project examples/flutter/android_slice generate flutter
cd examples/flutter/android_slice
flutter run -d <emulator>
flutter test integration_test -d <emulator>   # showcase_test.dart, slice_test.dart, bench_test.dart
```

`integration_test/showcase_test.dart` runs every task on the device. `slice_test.dart` covers the binding features one at a time: overloads, callbacks, Kotlin `suspend` and `Flow`, typed constants, bytes and native views.
