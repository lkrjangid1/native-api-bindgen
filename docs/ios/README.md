# iOS / Apple (Flutter)

Status: **experimental**. Flutter on iOS works end to end for Objective-C APIs from Foundation and UIKit (see below for what has been tested). React Native on iOS and `diff ios` still return `E015 NOT_IMPLEMENTED` (exit code 2).

## How it works

```
Xcode SDK headers ──libclang (Xcode toolchain, dart:ffi)──▶ Native IR (apple) ──▶ Dart over package:objective_c
```

1. **Discovery**: `xcode-select -p`, `xcrun --sdk iphonesimulator|iphoneos --show-sdk-path/--show-sdk-version`, `xcodebuild -version`. Nothing is downloaded or copied.
2. **Extraction** (`packages/native_api_ios`): framework umbrella headers are parsed with libclang's stable C API, loaded from `XcodeDefault.xctoolchain/usr/lib/libclang.dylib`. Extracted: classes, protocols, categories (merged into their class), methods and selectors, properties (readonly, class, custom getters such as `isHidden`), designated `init` families, `NS_ENUM`/`NS_OPTIONS` values (exact, including 64-bit unsigned), structs, nullability (including `NS_ASSUME_NONNULL` and macro-qualified types), and per-platform availability (`introduced`/`deprecated`/`obsoleted`/`unavailable`).
3. **Planning** (`packages/native_api_flutter_ios`): decides per member what the target can express; everything skipped carries a diagnostic code (see below).
4. **Emission**: one Dart library per framework (`apple/uikit.dart`, …), typed `objc_msgSend` trampolines (`apple/_msgsend.dart`, one per native signature, with the x86_64 `stret`/`fpret` variants), runtime helpers (`apple/_runtime.dart`) and an umbrella `apple.dart`. Classes and protocols become Dart extension types over `objc.ObjCObject`; types that `package:objective_c` already provides (`NSString`, `NSArray`, `NSObject`, `NSError`, …) are referenced, not regenerated.

## Configuration

```yaml
platform:
  ios:
    sdk: auto            # iphonesimulator (default) or iphoneos
    minVersion: "15.0"   # the app's deployment target; newer APIs are guarded
    frameworks: [Foundation, UIKit]   # headers to parse
    include: []          # frameworks to generate entirely
    classes: [UIDevice, UIView, UIViewController]
    entries: []          # dependency-aware roots
    depth: 1
output:
  dir: lib/src/generated
```

```sh
native-api-bindgen generate ios                    # from configuration
native-api-bindgen generate ios --class UIKit.UIDevice --depth 0
native-api-bindgen generate ios --framework UIKit  # a whole framework
native-api-bindgen inspect ios                     # SDK version + frameworks with public headers
```

The app needs `objective_c` (^9.5) and `ffi` (^2.1) as dependencies. Android and iOS output can share `output.dir`: each target keeps its own manifest (`.native_api_bindgen_manifest`, `.native_api_bindgen_manifest_ios`), so neither run deletes the other's files.

## Mapping

| Objective-C | Dart |
|---|---|
| class / protocol | `extension type X._(objc.ObjCObject)` with `X.as`, `X.fromPointer`, `X.isA` (classes) / `X.conformsTo` (protocols) |
| `+alloc`, `+new`, `-init…` | `X.alloc()`, `X.new$()`, `x.initWith…()`; ARC ownership follows the method family (`alloc`/`new`/`copy`/`mutableCopy`/`init` return owned references) |
| `@property` | getter / setter (class properties are `static`) |
| selector keywords after the first | named parameters (`addItem(item, atIndex: 2)`) |
| `nullable` | `T?` (`nil` ⇄ `null`) |
| `NS_ENUM` / `NS_OPTIONS` | `abstract final class` of `int` constants; values are `int` |
| struct (`CGRect`, …) | `ffi.Struct` subclass, passed and returned by value |
| `NSError **` (last parameter) | hidden; a `NO`/`nil` result with an error set throws `NativeObjCError(domain, code, description)` |
| API newer than `minVersion` | runtime guard: throws `objc.OsVersionError` on older iOS |
| deprecated API | `@Deprecated` with the iOS version |

## Not supported yet (with codes)

| Construct | Code |
|---|---|
| Blocks (completion handlers) | `E004` |
| Implementing protocols in Dart (delegates) | `E004` (info: protocols are usable for typing and calls) |
| Variadic methods, `SEL`, `Class` parameters, C arrays, bit-field structs | `E002` |
| Raw C pointers (`void *`) | exposed as `ffi.Pointer` (`E002` info, partial) |
| Types outside the generation closure | exposed as `objc.ObjCObject` (`E016` info) |
| `_`-prefixed (private) selectors | `E005` |
| `API_UNAVAILABLE(ios)` | `E012` |
| Swift-only APIs | not visible in Objective-C headers |

## Tested (2026-10-05, maintainer machine)

- Xcode 27.0, iPhoneSimulator SDK 27.0; `examples/flutter/ios_slice` integration tests: **12/12 passing** on an iPhone 17 simulator running iOS 26.4 (`flutter test integration_test -d <udid>`). The availability-guard test calls an iOS 27.0 API on the iOS 26.4 runtime and expects `OsVersionError`.
- Foundation + UIKit generated entirely: 1,527 types, 14,362 bound members, extraction + emission ≈ 0.5–0.6 s, `dart analyze`: 0 issues (`packages/native_api_flutter_ios/tool/gen_sdk.dart`). Only the example's APIs are runtime-tested.
- Fixture IR snapshot, golden Dart output, determinism, traceability and `dart analyze --fatal-infos` on goldens: `packages/native_api_ios/test`, `packages/native_api_flutter_ios/test` (macOS + Xcode only; skipped elsewhere).

Legal policy: `docs/legal/apple.md`.
