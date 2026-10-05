# tests/

| Directory | Contents |
|---|---|
| `golden/ir/` | canonical IR snapshots of the Java and Objective-C fixtures |
| `golden/flutter`, `golden/flutter-ios` | expected Dart for the fixtures |
| `golden/react-native`, `golden/react-native-ios` | expected TypeScript and member tables |
| `golden/swift` | expected `@objc` adapter source and Objective-C view |
| `runtime/jvm_fixtures/` | generated bindings on a host JVM, incl. Kotlin suspend (`tools/run_jvm_runtime_tests.sh`) |
| `legal/` | restricted-artifact fixtures are synthesised at test time in `packages/native_api_core/test/legal_audit_test.dart` |

Unit, generation, fuzz and CLI tests live next to each package in `packages/*/test`. Real-platform integration tests live in the example apps (`examples/flutter/*/integration_test`, `examples/react-native/slice/src/selfTests*.ts`); size and performance measurements in `tools/measure_*.py`, `*/bench*` and `docs/benchmarks`.
