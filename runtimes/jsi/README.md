# native-api-bindgen-runtime

The React Native runtime of native-api-bindgen: one pure C++ Turbo Module
(`NativeApiBindgen`) that installs `global.__nab`, plus the JSI host objects
that call Android APIs through JNI (`cpp/`) and iOS APIs through
Objective-C++ (`objc/`), and the TypeScript side (`ts/`).

Generated bindings (`native-api-bindgen generate react-native`) embed a copy
of these sources, so most apps do not need this package. The Java helpers
(`NabContext`, `NabInvocationHandler`, `NabContinuation`, `NabViews`,
`NabNativeViewManager`, `NabUiPackage`) are part of the generated library's
`android/java` directory.

- License: Apache-2.0
- Status: experimental; tested on an Android emulator and an iOS simulator.
- Not affiliated with or endorsed by Google, Apple or Meta.
