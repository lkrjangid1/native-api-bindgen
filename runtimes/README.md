# runtimes/

| Runtime | Location |
|---|---|
| Dart (Flutter/Android): availability guards, `NativeJavaException`, callback error policy, Kotlin `suspend` | `runtimes/dart/native_api_runtime` |
| JNI | [`package:jni`](https://pub.dev/packages/jni) (not vendored); React Native callback proxy in `runtimes/jni/java` |
| Objective-C (Flutter/iOS) | [`package:objective_c`](https://pub.dev/packages/objective_c) (not vendored) plus a generated `apple/_runtime.dart` |
| JSI (React Native) | `runtimes/jsi/cpp` (Turbo Module + JNI runtime), `runtimes/jsi/objc` (Objective-C++ runtime, module provider), `runtimes/jsi/ts` (TypeScript side) |

React Native runtime sources are embedded into the generators by `packages/native_api_react_native_{android,ios}/tool/embed_runtime.dart`; tests fail if the embedded copy drifts.
