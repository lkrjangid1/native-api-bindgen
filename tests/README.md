# tests/

| Directory | Contents |
|---|---|
| `golden/ir/` | canonical IR snapshot of `fixtures/java/basic` |
| `golden/flutter/basic`, `basic_ergonomic` | expected generated Dart for the fixtures (strict-native / ergonomic-dart) |
| `runtime/jvm_fixtures/` | runs generated fixture bindings on a host JVM (`tools/run_jvm_runtime_tests.sh`) |
| `legal/` | restricted-artifact fixtures are synthesised at test time in `packages/native_api_core/test/legal_audit_test.dart` so the repository itself stays clean |
| unit / generation / fuzz | live next to each package in `packages/*/test` |
| integration (real device) | `examples/flutter/android_slice/integration_test` |
| size | `tools/measure_size.py`, results in `docs/benchmarks/size.md` |
