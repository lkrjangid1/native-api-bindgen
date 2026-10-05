# Compatibility matrix

Only versions **actually exercised** are listed. "Tested" means automated tests ran against that version on 2026-10-05 on the maintainer machine (macOS 27.2 arm64). CI workflows exist (`.github/workflows`) but have not run yet because the repository has no remote; this table will be generated from CI once they do.

| Component | Tested | How |
|---|---|---|
| Dart SDK | 3.11.5 | all package tests; workspace requires ≥ 3.9 |
| Flutter | 3.41.9 (stable) | example app build, widget test, integration tests, release APK builds |
| `package:jni` / `jni_flutter` | 1.0.3 / 1.0.3 | generated bindings compile and run (host JVM + Android emulator) |
| Android platform parsed (full android.jar) | 36, 37.2 | full-jar extraction; 36 also full Flutter generation + `dart analyze` |
| Android platforms in diff | 35 → 36 | `diff android` |
| Android device (emulator) | API 37 (`Pixel_7` AVD, arm64) | 12 integration tests |
| Generated `minApi` guards | 24 | guard tests (device + host JVM) |
| Minor SDK versions | 36.1 availability (fixture), `SDK_INT_FULL` path | unit + host-JVM tests |
| JDK | OpenJDK 25.0.2 (fixtures compiled with `--release 17`) | fixture, golden, host-JVM runtime tests |
| CMake (host JNI helper) | 3.22.1 (from Android SDK) | `tools/run_jvm_runtime_tests.sh` |
| Xcode / iOS SDK | 27.0 / iPhoneSimulator 27.0 | libclang extraction; Foundation + UIKit full generation + `dart analyze` |
| iOS runtime (simulator) | 26.4 (iPhone 17) | 12 Flutter integration tests (`examples/flutter/ios_slice`, deployment target 15.0) |
| `package:objective_c` | 9.5.0 | generated iOS bindings compile and run |
| Kotlin (fixture library) | Kotlin 2.4.20, kotlinx-coroutines 1.10.2, Gradle 9.6.0 | suspend functions: 8 host-JVM tests (`tools/run_jvm_runtime_tests.sh`), 2 Flutter integration tests on the API 37 emulator |
| React Native on iOS | 0.87.1 (New Architecture, Hermes), CocoaPods 1.16.2 | release build for the iOS 26.4 simulator; 12 self-tests (`tools/run_rn_ios_tests.sh`) |
| React Native on Android | 0.87.1 (New Architecture, Hermes) | RN example release build; 12 on-device self-tests on API 37 emulator; Jest runtime tests |
| Node / TypeScript | 25.9.0 / 6.0.3 | `tsc --strict` on generated output (fixtures, slice, full android-36 SDK) |

## Known constraints

- `package:jni` ≥ 1.0 is required (generated code uses its extension-type API and `JImplementer`).
- Android platforms must include `data/api-versions.xml` for availability and non-SDK detection (all platforms tested do).
