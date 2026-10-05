# Performance (TRD §35)

Measured on 2026-10-05 on the maintainer's Apple-silicon Mac. **Emulator and simulator numbers are not device numbers**; they are useful for relative comparisons on the same machine only. Each value is the median of three runs (raw runs in the JSON files); per-call values are averages over a timed loop after a warm-up.

## Flutter on Android — profile mode, API 37 arm64 emulator

`examples/flutter/android_slice/integration_test/bench_test.dart` (`flutter drive --profile`), JSON: [`perf-2026-10-05-flutter-android.json`](perf-2026-10-05-flutter-android.json)

| Operation | Generated binding (JNI) | Hand-written MethodChannel |
|---|---|---|
| Instance call returning `int` (`Bundle.size()`) | 1.00 µs | 270.7 µs |
| Static call returning an object (`Uri.parse`) | 4.06 µs | — |
| String in + string out (`Uri.parse(s).toString()`) | 12.50 µs | 279.5 µs |
| No-op round trip | — | 267.2 µs |
| Java → Dart callback, synchronous (`Handler.dispatchMessage` → `Handler.Callback`) | 130.47 µs | — |
| `Handler.post` on the main Looper → Dart `Runnable` runs (median) | 28.0 ms (sync) / 29.2 ms (async) | — |

The `Handler.post` latency is dominated by when the main Looper dispatches the message in this setup (the synchronous and asynchronous callback variants are the same), not by the binding call itself.

## Flutter on iOS — debug (JIT), iPhone 17 simulator, iOS 26.4

Flutter supports profile/release builds only on physical iOS devices, so these are JIT numbers. `examples/flutter/ios_slice/integration_test/bench_test.dart`, JSON: [`perf-2026-10-05-flutter-ios.json`](perf-2026-10-05-flutter-ios.json)

| Operation | Generated binding (`objc_msgSend`) | Hand-written MethodChannel |
|---|---|---|
| Instance getter returning `NSInteger` (`UIView.tag`) | 34.4 ns | 20.4 µs |
| Class getter returning an object (`NSProcessInfo.processInfo`) | 197.1 ns | — |
| `NSString` set + get + convert (`UIViewController.title`) | 1.08 µs | 19.6 µs (echo) |
| Struct by value get + set (`UIView.frame`) | 117.4 ns | — |
| No-op round trip | — | 26.0 µs |

## React Native — release (Hermes bytecode)

`examples/react-native/slice/src/bench.ts`, run after the self-tests by `tools/run_rn_device_tests.sh` / `tools/run_rn_ios_tests.sh`.

Android (API 37 arm64 emulator), JSON: [`perf-2026-10-05-rn-android.json`](perf-2026-10-05-rn-android.json)

| Operation | Generated binding (JSI → JNI) |
|---|---|
| Instance call returning `int` (`Bundle.size()`) | 1.50 µs |
| Static call returning an object (`Uri.parse`, then `release()`) | 4.53 µs |
| Call returning a string (`Uri.toString()`) | 1.88 µs |
| Promise variant (`Bundle.sizeAsync()`), JNI on a worker thread | 424 µs |

iOS (iPhone 17 simulator, iOS 26.4), JSON: [`perf-2026-10-05-rn-ios.json`](perf-2026-10-05-rn-ios.json)

| Operation | Generated binding (JSI → Objective-C++ → `NSInvocation`) |
|---|---|
| Foundation getter returning `NSUInteger` (`activeProcessorCount`, JS thread) | 1.14 µs |
| Class getter returning an object (`NSProcessInfo.processInfo`, then `release()`) | 2.33 µs |
| Getter returning a string (`processName`) | 0.90 µs |
| UIKit getter (`UIView.tag`, synchronous hop to the main thread) | 9.98 µs |
| UIKit struct get + set (`UIView.frame`, two main-thread hops) | 20.68 µs |
| Promise variant (`NSFileManager.fileExistsAtPathAsync`) | 11 µs |

No hand-written React Native module was benchmarked for comparison.

## Not measured yet

Physical devices; release-mode Flutter on iOS; byte buffers; callback latency on React Native; memory per handle.
