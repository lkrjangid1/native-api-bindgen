# Test strategy

<!-- description: How native-api-bindgen is tested: unit, fuzz, fixture, golden and integration tests on emulators and simulators, and where each layer runs. -->

| Layer | What | Where | Runs on |
|---|---|---|---|
| Unit | IR IDs, JSON round-trip, validation; config; path guard; logging; class-file & signature parsers; api-versions/annotations parsing; type mapping; identifier escaping; overload naming | `packages/*/test` | any OS (CI ubuntu) |
| Fuzz | truncated/mutated class files, zips, XML, IR JSON → must return diagnostics, never throw uncaught | `packages/native_api_android/test/fuzz_test.dart`, `packages/native_api_ir/test/fuzz_test.dart` | any OS |
| Fixtures | synthetic Java (`fixtures/java/basic`) compiled with `javac --release 17` at test time → parse → IR snapshot | `packages/native_api_android/test/fixture_test.dart` | needs JDK |
| Golden | generated Dart for fixtures compared byte-for-byte with `tests/golden/flutter/basic`; goldens are also analyzed with `dart analyze` | `packages/native_api_flutter_android/test` | needs JDK |
| Real SDK | parse local android-N, assert slice signatures, availability, nullability | `packages/native_api_android/test/real_sdk_test.dart` (skipped with reason when no SDK) | dev machines / android CI job |
| Determinism | generate twice, compare bytes; `verify-reproducible` command | CLI tests | any OS |
| Legal | scanner detects Mach-O, `.framework`, Apple header banners, class files/jar, large doc dumps | `packages/native_api_core/test/legal_*` + `tests/legal` fixtures | any OS |
| Integration (real device/emulator) | generated bindings call the real Android framework from Flutter | `examples/flutter/android_slice/integration_test` | emulator |
| Size | release APK sizes for baseline / imported-unused / one-API | `docs/benchmarks/size.md` | local / android CI |

Rules: no test may depend on network; golden tests must be stable across machines (no absolute paths, no timestamps); tests that need a JDK or SDK skip with an explicit reason rather than pass vacuously.
