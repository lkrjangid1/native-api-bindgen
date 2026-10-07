# Performance (TRD §35)

<!-- description: Measured call overhead of generated Flutter and React Native bindings versus MethodChannel on Android and iOS, plus byte transfers and callback latency. -->

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

## Byte transfers (TRD §36) — single runs

JSON: [`bytes-2026-10-05.json`](bytes-2026-10-05.json). Each value is the mean of 10 iterations after one warm-up (a single run, not a median of three).

| Path | 1 MB | 16 MB |
|---|---|---|
| Flutter Android (profile, emulator): `Uint8List` → `byte[]` → `Arrays.copyOf` → `Uint8List` (`byteArrayOf` / `bytesOf`) | 1.80 ms | 32.9 ms |
| Same through a hand-written MethodChannel | 9.02 ms | 53.8 ms |
| Flutter Android: fill a direct `ByteBuffer` (`directBufferOf`, then a zero-copy `asUint8List` view) | 2.33 ms | 5.99 ms |
| Flutter iOS (debug, simulator): `nsDataFromBytes` (one copy) | 0.076 ms | 2.47 ms |
| Flutter iOS: `nsDataView` (zero-copy view) | 0.0002 ms | 0.0002 ms |
| Flutter iOS: `NSData.toList()` (copy) | 0.21 ms | 2.08 ms |
| React Native Android (release, emulator): `Uint8Array` → `byte[]` → `Arrays.copyOf` → `Uint8Array` | 1.61 ms | 30.9 ms |
| React Native Android: same with `number[]` (element by element) | 99.6 ms | — |
| React Native iOS (release, simulator): `nsDataFromBytes` + `bytesFromNSData` | 0.153 ms | 1.75 ms |

## Memory and callback latency (WP7) — emulator / simulator

JSON: [`perf-2026-10-05-wp7.json`](perf-2026-10-05-wp7.json).

| Measurement | Value |
|---|---|
| Flutter Android (profile): RSS per live generated handle (`Bundle`), 50k handles after a warm-up, median of 3 runs | 216 bytes (runs: 216, 470, 216) |
| Flutter iOS (debug): RSS per live `NSOperationQueue` handle (Dart wrapper + native object), 50k, 3 runs | 906 / 923 / 930 bytes |
| React Native Android (release): PSS per live `Bundle` handle, 10k handles, single run | 46 bytes |
| React Native Android: `Handler.post` → JS `Runnable` (async callback), median of 200, single run | 125 µs |
| React Native iOS (release): `NSOperationQueue` block (background thread) → JS, median of 200, single run | 13 µs |

Flutter Android's `Handler.post` → Dart latency (median 46653 µs over the 3 runs) is dominated by when the main Looper runs the posted message during frame work in profile mode, not by the binding call; React Native's JS thread is separate from the main thread, so its posted callbacks arrive faster.

## Not measured yet

Physical devices (none measured: no consent was given to install on the attached phone); release-mode Flutter on iOS (the simulator supports debug only).
