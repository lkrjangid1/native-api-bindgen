# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/) for the generator/runtime (platform SDK versions are tracked separately, see `docs/versioning.md`).

## [Unreleased]

### Added
- Example apps now do real tasks through generated bindings, the same set in Flutter and React Native on Android and iOS:
  - a live device dashboard (battery, memory, storage, network or thermal state);
  - text-to-speech (`TextToSpeech` with an `OnInitListener` implemented in Dart/JS; `AVSpeechSynthesizer`);
  - the share sheet, the clipboard and a note that persists across restarts (`SharedPreferences`, `NSUserDefaults`);
  - haptics (`VibrationEffect`, guarded for API < 26; `UIImpactFeedbackGenerator`) and opening URLs;
  - opening the location settings: Android's Location page (`Settings.ACTION_LOCATION_SOURCE_SETTINGS`) and the app's permission page (`ACTION_APPLICATION_DETAILS_SETTINGS`); on iOS, the app's page in Settings.

  Each task has an on-device test: `integration_test/showcase_test.dart` (Flutter) and the "Showcase" self-tests (React Native).
- React Native iOS runtime: `nsString(text)` creates an `NSString` object for `id`-typed parameters, such as `-[NSUserDefaults setObject:forKey:]` and `NSArray` items.

## [0.1.0-beta.1] - 2026-10-06

First public beta, published to pub.dev. APIs and generated output may still change between beta releases.

- Distribution: Dart packages on pub.dev, `native-api-bindgen-runtime` on npm, prebuilt CLI binaries (macOS arm64/x64, Linux x64/arm64) on GitHub Releases and a Homebrew tap (`brew install lkrjangid1/tap/native-api-bindgen`). See `docs/releasing.md`.

### Added
- Monorepo foundation: Native IR, core (config, diagnostics, logging, path guard, license audit), CLI.
- Android SDK discovery and pure-Dart `android.jar` parser with `api-versions.xml` / `annotations.zip` enrichment.
- Flutter Android generator targeting `package:jni`.
- Synthetic Java fixtures, golden tests, fuzz tests, legal scanner tests.
- Flutter Android vertical-slice example with on-device integration tests (12 passing on an API 37 emulator).
- Host-JVM runtime tests for generated bindings (`tools/run_jvm_runtime_tests.sh`).
- CLI: init, detect, doctor, inspect, generate, update, diff, coverage, graph, explain, why-generated, why-skipped, audit-license, verify-reproducible, clean.
- Release-APK size benchmarks (`tools/measure_size.py`, `tools/measure_rn_size.py`, `docs/benchmarks/size.md`).
- `license-audit-allowlist.yaml`: checksum-pinned reviewed exceptions (never waives BLOCK).

- React Native (Android, New Architecture): TypeScript bindings over a JSI/JNI runtime installed by one pure C++ Turbo Module; Promise variants; Java interfaces implemented in JS; `generate react-native`; RN example with on-device self-tests; `tools/run_rn_device_tests.sh`, `tools/measure_rn_size.py`.
- iOS (Flutter): Apple SDK discovery and Objective-C extraction through the Xcode toolchain's libclang (`native_api_ios`); Dart bindings over `package:objective_c` (`native_api_flutter_ios`); `generate ios`, `inspect ios`, `doctor` libclang check; `NSError **` → `NativeObjCError`; iOS availability guards; synthetic Objective-C fixtures with IR snapshot and goldens; `examples/flutter/ios_slice` with 12 simulator integration tests.
- React Native (iOS): TypeScript bindings over an Objective-C++ JSI runtime (`NSInvocation` with runtime method signatures, UIKit on the main thread, structs incl. anonymous ones, `NSError **` → `NativeObjCError`, `NSException` → `NativeObjCException`, Promise variants); `generate react-native-ios`; generated podspec + `NabModuleProvider`; the RN example (renamed `examples/react-native/slice`) runs 12 self-tests on an iOS simulator (`tools/run_rn_ios_tests.sh`).
- Static website (`website/src`, built by `tools/build_website.dart`: 11 pages, numbers injected from `docs/benchmarks`, build-time checks for links, titles, descriptions, tag balance and size budgets) and a GitHub Pages workflow.
- Performance benchmarks (`docs/benchmarks/performance.md`): Flutter Android (profile) and iOS (debug) generated calls vs. MethodChannel, callback latency, React Native JSI calls (release).
- Swift-only APIs (Layer 2): `swift-symbolgraph-extract` discovery, generated `@objc` adapters + Objective-C view + podspec (`platform.ios.swift`), bound through the regular Objective-C pipeline; Swift fixture module with goldens and simulator tests.
- Android library artifacts (`platform.android.libraries`, `--jar`: jars, AARs, class directories) bound as library APIs.
- Kotlin `suspend` functions as Dart `Future`s (`native_api_runtime` `callSuspend` over `package:jni`'s `PortContinuation`); Kotlin fixture library (`fixtures/kotlin/basic`) with host-JVM and on-device tests.
- IR schema 2: Apple module-qualified IDs, per-platform availability, unsigned primitives, pointer and block type references (schema 1 still reads).

### Changed
- `native-api-bindgen docs`: static per-symbol API reference in `generated-docs/` (native/generated symbol, availability, threading, permissions, reason codes, provenance, official links; metadata only).
- Website: TRD §69/§70 hero and buttons, Problem / Solution / Coverage / Performance / Legal / Roadmap sections, `docs.html` and `examples.html`, footer links (GitHub, license, security and contributing appear when the repository URL is known: `--repo-url` / `NAB_REPO_URL`, set automatically in the Pages workflow), §79 disclaimer. Coverage data committed in `docs/benchmarks/coverage-2026-10-05-*.json`.
- npm: `runtimes/jsi` is the package `native-api-bindgen-runtime` (dry-run checked by `tools/check_publish.sh`).
- Measurements (WP7): iOS release app sizes (`tools/measure_ios_size.py`: full Foundation + UIKit bindings add no AOT code over a 6-class slice), AAB sizes (`measure_size.py --aab`), Android cold start (`tools/measure_startup.py`, emulator-only by default), memory per handle and React Native callback latency (bench suites). Physical devices not measured.
- Native UI layer (TRD §37): Flutter plugin `runtimes/flutter/native_api_ui` (`NativeView.android` / `NativeView.ios`) and React Native `<NativeView>` (view managers + runtime view registry) host views created through the bindings; tested on all four target/platform pairs. React Native Android `CharSequence` parameters accept JS strings.
- Byte buffers: React Native Android `byte[]` is `Uint8Array` (**breaking** for results; `number[]` still accepted as input), one region copy through an `ArrayBuffer` (1 MB round trip 1.61 ms vs 99.6 ms as `number[]`); `java.nio.ByteBuffer` maps to `package:jni`'s `JByteBuffer`; runtime helpers `bytesOf` / `byteArrayOf` / `directBufferOf` (Dart Android), `nsDataView` / `nsDataFromBytes` (Flutter iOS), `nsDataFromBytes` / `bytesFromNSData` / `nsArrayItems` (React Native iOS). Benchmarks in `docs/benchmarks/bytes-2026-10-05.json`.
- Swift Layer 2: collections (`[T]`, `[String: T]`), `Int`/`String` raw-value enums, `throws` (→ `NSError **`) and `async` (→ completion handler, `Future` in Flutter for primitive results) are adapted. WeatherKit 183/615 members adaptable (was 89/446); all SDK adapters type-check.
- React Native iOS: Objective-C protocols implemented in JavaScript (`Proto.implement({...})`, generic `forwardInvocation:` runtime object); 192 Foundation/UIKit protocols. Flutter iOS protocols remain `E004` (need native trampolines).
- iOS blocks: Flutter binds `NS_NOESCAPE` blocks (synchronous closure blocks) and escaping primitive `void` blocks (`NativeCallable.listener`), plus `fooAsync` `Future` forms for completion handlers; React Native binds blocks through generated per-signature Objective-C++ factories (`NabBlocksObjC.mm`, `B<key>;` codes), delivering off-thread calls to the JS thread with retained arguments. `NS_NOESCAPE` is extracted into the IR. Foundation + UIKit: Flutter 141 / React Native 270 block parameters bound.
- iOS threading: main-actor isolation (`NS_SWIFT_UI_ACTOR`, `NS_SWIFT_NONISOLATED`) extracted into the IR. Flutter iOS documents it and checks it in debug builds (`NativeThreadingError`, E013; `isMainThread()`); React Native iOS dispatches by IR threading instead of "all of UIKit" (6,789 of 12,706 rows on the iOS 27.0 SDK). Foundation + UIKit: 559/1,527 types and 6,708/12,886 methods main-actor isolated.
- Kotlin (Android): pure-Dart `kotlin.Metadata` reader (bounded, fuzz-tested). Suspend results are non-null when Kotlin says so (**breaking** for generated Dart: `Future<String?>` → `Future<String>`), type-argument and member nullability, Kotlin parameter names, default-argument notes (`E002` info). `Flow<T>` → `Stream<T>` (Flutter, `rt.collectFlow`). React Native: suspend functions → `Promise<T>` (`NabContinuation`, settled on the JS thread). R8 keep rules for library classes and the reflective coroutine classes. Fixed: a suspend function resuming with `null` threw in `callSuspend`; Kotlin setter parameter names (`<set-?>`) produced invalid TypeScript.
- Typed constants (Android, Flutter + React Native): `@IntDef`/`@LongDef`/`@StringDef` sets from `annotations.zip` generate Dart `const` extension types implementing `int`/`String` (flags: `|`, `has`) and TS `as const` objects + union types; ergonomic modes type results with them; parameters are unchanged. android-36: 851 sets, 2,109 typed use sites; full outputs analyze / type-check with zero errors in strict and ergonomic modes.
- Bean properties (Android, Flutter + React Native): `getX`/`isX` + matching `setX` also generate a property backed by those methods (additive; the methods remain). android-36: 12,513 Dart / 11,886 TypeScript properties; full outputs analyze / type-check with zero errors.
- **Breaking (generated Dart, Android):** Java generics are Dart type parameters instead of erasure (`GenericClass<$T>`, generic methods, `JList<JString?>`); `java.util` collections and boxed numbers use `package:jni` wrappers. Full android-36 output analyzes with zero issues.
- iOS parity in the CLI: `diff ios` (IR snapshots `ir-ios-<sdk>.json` or `current`), `update` regenerates configured iOS targets (and works without an Android selection), `coverage --target`, and `explain` / `why-*` / `inspect <symbol>` read the iOS, React Native iOS and Swift states. No command returns `E015` any more.
- Tooling: `tools/ci_local.sh` runs the CI steps locally; the Kotlin fixture has a checksum-verified Gradle wrapper; the React Native Android C++ check finds a JDK without `JAVA_HOME`; `release-check.yml` also runs iOS, React Native, website, size and package validation.
- State files (`ir.json`, `binding_map.json`) are written as streams: whole-SDK generation peak memory 1.08 GB → 416 MB (same bytes).
- `generate react-native` generates every configured platform; configured iOS generation is skipped with a warning off macOS.
- Objective-C member naming is shared by the Dart and TypeScript targets (`ObjCMemberResolver`).
- `writeGeneration` takes a per-target manifest name; Android and iOS output can share a directory.
- Configuration: `platform.ios` (`sdk`, `minVersion`, `frameworks`, `include`, `classes`, `entries`, `depth`).
- `audit-license`: Apple-derived generated bindings are reported (WARN); Clang AST dumps and precompiled headers are blocked.
- The JVM-target planner moved to `native_api_generator` (shared by Flutter and React Native).
- Configuration: `generation.typescriptMode`, `output.reactNativeDir`.

### Fixed
- Same-thread synchronous callbacks now wake the Dart event loop so awaiting code resumes promptly.

### Legal/Source policy
- Default `distribution.generatedArtifacts: local-only` and `documentationMode: links-only`.
- Documented Android/Apple/Flutter/React Native source policies (not legal advice).
