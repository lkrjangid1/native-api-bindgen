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
- Release-APK size benchmark (`tools/measure_size.py`, `docs/benchmarks/size.md`).

### Fixed
- Same-thread synchronous callbacks now wake the Dart event loop so awaiting code resumes promptly.

### Legal/Source policy
- Default `distribution.generatedArtifacts: local-only` and `documentationMode: links-only`.
- Documented Android/Apple/Flutter/React Native source policies (not legal advice).
