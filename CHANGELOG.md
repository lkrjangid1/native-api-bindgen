# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/) for the generator/runtime (platform SDK versions are tracked separately, see `docs/versioning.md`).

## [Unreleased]

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
- IR schema 2: Apple module-qualified IDs, per-platform availability, unsigned primitives, pointer and block type references (schema 1 still reads).

### Changed
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
