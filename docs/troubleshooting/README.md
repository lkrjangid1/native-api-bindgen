# Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `E001 SDK_NOT_FOUND` | Set `ANDROID_HOME` or `platform.android.sdk`; install the platform with `sdkmanager "platforms;android-36"`. The tool never downloads SDKs. |
| A method is missing | `native-api-bindgen why-skipped '<Type#member>'` shows the reason code. Types outside the closure appear as `JObject` (`E016`): add them with `--entry`. |
| `NativeApiUnavailableException` | The API is newer than the device (`E012`). Check `AndroidApi.isAtLeast(n)` before calling. |
| `UseAfterReleaseError` | The object was `release()`d/`dispose()`d; don't reuse it. |
| Callback from a background Java thread hangs | The Java thread waits for Dart by default while the isolate waits for that thread. Pass `<method>$async: true` for `void` listeners. |
| `Future` completed in a callback doesn't resume until something else happens | Fixed in 0.1.0-dev.1: generated trampolines wake the event loop after same-thread callbacks. Regenerate bindings. |
| Desktop JNI tests: CMake cannot find JNI | Set `JAVA_HOME`; `tools/run_jvm_runtime_tests.sh` passes explicit JNI paths to CMake. |
| `'Text' is imported from both …` (or `View`, `Color`, …) | Android and Flutter share names. Import the bindings with a prefix: `import '…/bindings.dart' as android;` |
| `ambiguous export` | Two packages declare the same class name; the second is hidden from `bindings.dart` — import its library directly. |
