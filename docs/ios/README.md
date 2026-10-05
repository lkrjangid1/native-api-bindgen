# iOS / Apple (Flutter)

Status: **experimental**. Flutter and React Native on iOS work end to end for Objective-C APIs from Foundation and UIKit (see below for what has been tested). React Native details: `docs/react-native/README.md`.

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
native-api-bindgen inspect UIDevice#systemName     # IR of a generated symbol
native-api-bindgen coverage --target ios           # android | ios | ios-rn | ios-swift | all
native-api-bindgen why-skipped UIKit.UIView#-…     # reason codes for a skipped member
native-api-bindgen diff ios --from ir-ios-26.4.json --to current  # snapshots are written by generate ios
native-api-bindgen update                          # regenerates every configured Android and iOS target
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

## Threading (main actor)

The extractor reads Swift concurrency annotations from the headers, the way Swift's importer does (`-D__SWIFT_ATTR_SUPPORTS_SENDABLE_DECLS`): `NS_SWIFT_UI_ACTOR` / `NS_SWIFT_MAIN_ACTOR` on a class, protocol, category or member marks it `mainThread`; `NS_SWIFT_NONISOLATED` opts a member out (`anyThread`). libclang does not expose `swift_attr`, so the attribute's expansion site in the header is read.

- Flutter: main-actor members document it and check it with `assert(rt.checkMainThread(...))`, which throws `NativeThreadingError` (E013) off the main thread in debug builds and costs nothing in release. On iOS the root isolate runs on the main thread; background isolates may call nonisolated APIs (e.g. Foundation).
- React Native: main-actor members (and `+alloc`/`+new` of main-actor classes) are invoked on the main thread; everything else runs on the calling JS thread. This replaces the earlier rule "all of UIKit on the main thread" (`RnObjCOptions.mainThreadModules` remains as an override).
- Measured (iOS 27.0 SDK, Foundation + UIKit): 559 of 1,527 types and 6,708 of 12,886 methods are main-actor isolated, 39 methods are nonisolated; React Native dispatches 6,789 of 12,706 member rows to the main thread.

## Swift-only APIs (Layer 2: generated `@objc` adapters)

Swift APIs that are not visible to Objective-C are discovered with the official toolchain and wrapped:

1. `xcrun swiftc -emit-module` (for a module built from sources) and `xcrun swift-symbolgraph-extract` produce the module's public symbol graph (kept in a temporary directory, never written to the project).
2. For the Objective-C-representable subset (classes and structs; `Int`, `UInt`, `Double`, `Float`, `Bool`, `String`, `Date`, `Data`, `URL`, other adapted types, optionals of object types), `<Module>Adapters.swift` defines `@objc(<Module>_<Type>)` classes with explicit selectors that wrap the Swift value (`wrapped`), plus `NativeApiSwiftAdapters.podspec`.
3. A matching Objective-C interface is fed through the same libclang pipeline as the SDK headers, so the Dart bindings (`apple/swiftadapters.dart`) come from the regular emitter.

```yaml
platform:
  ios:
    swift:
      adaptersDir: ios/NativeApiSwiftAdapters   # add: pod 'NativeApiSwiftAdapters', :path => 'NativeApiSwiftAdapters'
      modules:
        - name: NABSwiftFixtures                  # a pod of the same name provides the module
          sources: [../../../fixtures/swift/basic/NABSwiftFixtures.swift]
        - name: WeatherKit                        # SDK module: no sources
          types: [Weather]
```

Selectors: the first argument label is appended to the base name (`increment(by:)` → `incrementBy:`, `init(start:label:)` → `initWithStart:label:`). APIs newer than `minVersion` carry `@available` / `API_AVAILABLE`. Not adapted (with reasons): closures and `async` (`E004`), generics (`E003`), tuples, collections, enums, protocols, `throws`, failable initializers, members colliding with `NSObject` (`E002`), iOS-unavailable APIs (`E012`). Adapters copy values, so object identity is not preserved across calls; `alloc()` must be followed by one of the adapter's `init…` methods.

Measured with Xcode 27.0 (`packages/native_api_ios/tool/swift_sdk_report.dart`, deployment target 18.0): of the members of three Swift-only SDK modules, 8 of 111 (TipKit), 71 of 3,466 (Charts) and 89 of 446 (WeatherKit) are adaptable today; the generated adapters for all three type-check with zero errors. The synthetic fixture (`fixtures/swift/basic`) runs on the iPhone 17 / iOS 26.4 simulator (3 integration tests in `examples/flutter/ios_slice`).

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
| Swift-only APIs outside the adaptable subset | see "Swift-only APIs" above |

## Tested (2026-10-05, maintainer machine)

- React Native 0.87.1 (`examples/react-native/slice`, release build with bundled JS): **12/12 self-tests passing** on the same iPhone 17 / iOS 26.4 simulator (`tools/run_rn_ios_tests.sh`). All of Foundation + UIKit as React Native bindings: 15,401 bound members, TypeScript type-checks with zero errors, C++ tables compile with `-Werror`.

- Xcode 27.0, iPhoneSimulator SDK 27.0; `examples/flutter/ios_slice` integration tests: **12/12 passing** on an iPhone 17 simulator running iOS 26.4 (`flutter test integration_test -d <udid>`). The availability-guard test calls an iOS 27.0 API on the iOS 26.4 runtime and expects `OsVersionError`.
- Foundation + UIKit generated entirely: 1,527 types, 14,362 bound members, extraction + emission ≈ 0.5–0.6 s, `dart analyze`: 0 issues (`packages/native_api_flutter_ios/tool/gen_sdk.dart`). Only the example's APIs are runtime-tested.
- Fixture IR snapshot, golden Dart output, determinism, traceability and `dart analyze --fatal-infos` on goldens: `packages/native_api_ios/test`, `packages/native_api_flutter_ios/test` (macOS + Xcode only; skipped elsewhere).

Legal policy: `docs/legal/apple.md`.
