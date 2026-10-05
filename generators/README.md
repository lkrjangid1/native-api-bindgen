# generators/

Generator implementations live in Dart packages so they share one toolchain:

| Target | Package |
|---|---|
| Android IR (parser) | `packages/native_api_android` |
| Flutter (Android, Dart/JNI) | `packages/native_api_flutter_android` |
| Shared services | `packages/native_api_generator` |
| Apple / Flutter iOS / React Native | not implemented (`packages/native_api_ios`, …) |

This directory is kept to mirror the architecture in TRD §6; it intentionally contains no code.
