# generators/

Generator implementations live in Dart packages so they share one toolchain; this directory mirrors the architecture in TRD §6 and intentionally contains no code.

| Target | Package |
|---|---|
| Android IR (parser, library jars, Kotlin suspend detection) | `packages/native_api_android` |
| Apple IR (libclang Objective-C extraction, Swift symbol graphs, `@objc` adapters) | `packages/native_api_ios` |
| Flutter / Android (Dart over `package:jni`) | `packages/native_api_flutter_android` |
| Flutter / iOS (Dart over `package:objective_c`) | `packages/native_api_flutter_ios` |
| React Native / Android (TypeScript + JSI/JNI tables) | `packages/native_api_react_native_android` |
| React Native / iOS (TypeScript + JSI/Objective-C++ tables) | `packages/native_api_react_native_ios` |
| Shared services (type mapping, planners, naming, output) | `packages/native_api_generator` |
