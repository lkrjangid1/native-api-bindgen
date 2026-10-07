# Flutter / Dart target

<!-- description: How generated Flutter bindings call Android APIs through package:jni without MethodChannel: generated code shape, runtime, guards and usage. -->

Generated code uses only the officially supported Dart↔Java interop path: [`package:jni`](https://pub.dev/packages/jni) (the runtime used by `jnigen`). There is **no MethodChannel** in the generated API surface. `package:jni_flutter` is used only by apps to obtain the application `Context` / current `Activity`.

- Each Java type → Dart extension type over `JObject` (zero-cost, tree-shakable, no registry).
- Strict-native mode (default) keeps JNI types visible (`JString`, `JIntArray`); `ergonomic-dart` maps `String` to Dart `String` with automatic conversion/release.
- Lifecycle, callbacks and threading: see `docs/architecture/lifecycle.md`.
- iOS: Dart bindings over [`package:objective_c`](https://pub.dev/packages/objective_c); see `docs/ios/README.md`.

Runtime dependencies (pub.dev):

```yaml
dependencies:
  jni: ^1.0.3
  jni_flutter: ^1.0.3
  objective_c: 9.5.0
  native_api_runtime: ^0.1.0-beta.1
  native_api_ui: ^0.1.0-beta.1     # optional: native views
```
