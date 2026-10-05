# Changelog

All notable changes to this project are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning: [SemVer](https://semver.org/) for the generator/runtime (platform SDK versions are tracked separately, see `docs/versioning.md`).

## [Unreleased]

### Added
- Monorepo foundation: Native IR, core (config, diagnostics, logging, path guard, license audit), CLI.
- Android SDK discovery and pure-Dart `android.jar` parser with `api-versions.xml` / `annotations.zip` enrichment.
- Flutter Android generator targeting `package:jni`.
- Synthetic Java fixtures, golden tests, fuzz tests, legal scanner tests.
- Flutter Android vertical-slice example with on-device integration tests.

### Legal/Source policy
- Default `distribution.generatedArtifacts: local-only` and `documentationMode: links-only`.
- Documented Android/Apple/Flutter/React Native source policies (not legal advice).
