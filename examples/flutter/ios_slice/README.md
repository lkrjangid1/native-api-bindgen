# Flutter on iOS: native tasks from Dart

Every native call in this app goes through Dart bindings that `native-api-bindgen` generated from the Xcode SDK headers (Foundation, UIKit, AVFAudio), over `package:objective_c`. There is no platform channel, no plugin per API and no hand-written Swift.

| Task | iOS APIs |
|---|---|
| Live device dashboard (refreshes every 3 s) | `UIDevice` battery monitoring, `NSProcessInfo` (thermal state, memory, cores, uptime, Low Power Mode), `NSFileManager attributesOfFileSystemForPath:error:` |
| Speak text | `AVSpeechSynthesizer`, `AVSpeechUtterance`, `AVSpeechSynthesisVoice` |
| Share text | `UIActivityViewController`, presented from the key window found through `UIApplication.connectedScenes` |
| Copy, then paste back | `UIPasteboard.generalPasteboard` |
| Note that survives restarts | `NSUserDefaults` |
| Haptics | `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator` |
| App settings (location permission) | `openURL:` with the value of `UIApplicationOpenSettingsURLString`. iOS has no public URL for the system Location Services page. |
| Open a URL | `UIApplication openURL:options:completionHandler:`; the completion block is a Dart callback |

Code: `lib/showcase.dart` (tasks) and `lib/main.dart` (UI). The selected classes are listed in `native_api_bindgen.yaml`.

```sh
# from the repository root (macOS with Xcode)
dart run native_api_bindgen --project examples/flutter/ios_slice generate ios
cd examples/flutter/ios_slice
flutter run -d <simulator>
flutter test integration_test -d <simulator>   # showcase_test.dart, slice_test.dart, bench_test.dart
```

`integration_test/showcase_test.dart` runs every task on the simulator. `slice_test.dart` covers the binding features one at a time: structs, `NSError **`, blocks, main-thread checks, Swift adapters and native views.
