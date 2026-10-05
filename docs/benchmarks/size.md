# Binary size

Measured 2026-10-05 with `tools/measure_size.py --platform 36` (Flutter 3.41.9, `package:jni` 1.0.3, release APK, `--target-platform android-arm64`, macOS arm64 host). Raw data: [`size-2026-10-05-android36.json`](size-2026-10-05-android36.json). Uncompressed entry sizes are read from the APK; APK size is the file size.

| Variant | APK bytes | Δ APK vs baseline | `libapp.so` (Dart AOT) | `libdartjni.so` | `classes*.dex` |
|---|---:|---:|---:|---:|---:|
| baseline (no bindings) | 14,426,402 | — | 2,687,920 | 0 | 526,004 |
| bindings imported, unused | 14,776,680 | +350,278 | 2,687,920 | 329,884 | 533,700 |
| one API (`Context.getPackageName`), slice bindings (24 types) | 14,842,216 | +415,814 | 2,753,456 | 329,884 | 533,700 |
| one API, **bindings for every android.jar package** (6,196 types, 95,888 members, ~1.1M lines) | 14,842,216 | +415,814 | 2,753,456 | 329,884 | 533,700 |
| full slice example (`examples/flutter/android_slice`, UI + all demos) | 15,759,688 | +1,333,286 | 3,670,960 | 329,884 | 533,724 |

## Findings

- **Unused generated APIs are not included.** The app using one API with bindings generated for the entire SDK is byte-identical in size to the same app with a 24-type slice. With bindings imported but nothing called, `libapp.so` is identical to the baseline.
- The fixed overhead of the approach comes from `package:jni`'s native helper (`libdartjni.so`, 329,884 bytes uncompressed for arm64) and its Java support classes (+7,696 bytes of dex) — not from generated code.
- Calling one API added 65,536 bytes to `libapp.so`. This equals one 64 KiB segment-alignment step of the AOT snapshot, so the true code delta is not resolvable at this granularity.

## Not measured yet

Startup time, memory, AAB/split sizes and other ABIs. No claims are made about them.
