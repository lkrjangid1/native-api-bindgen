# Flutter / Dart target

Generated code uses only the officially supported Dart↔Java interop path: [`package:jni`](https://pub.dev/packages/jni) (the runtime used by `jnigen`). There is **no MethodChannel** in the generated API surface. `package:jni_flutter` is used only by apps to obtain the application `Context` / current `Activity`.

- Each Java type → Dart extension type over `JObject` (zero-cost, tree-shakable, no registry).
- Strict-native mode (default) keeps JNI types visible (`JString`, `JIntArray`); `ergonomic-dart` maps `String` to Dart `String` with automatic conversion/release.
- Lifecycle, callbacks and threading: see `docs/architecture/lifecycle.md`.
- iOS (Objective-C via `package:objective_c`) is not implemented yet.
