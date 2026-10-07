# Flutter / Dart policy

<!-- description: Policy for Flutter and Dart: package:jni as a normal pub dependency, the documented Java interop path, no MethodChannel, and trademark notes. -->

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

- Generated Flutter bindings depend on `package:jni` (BSD-3-Clause, published by the Dart team). It is a normal pub dependency and is not vendored.
- Interop follows the Dart team's documented Java interop approach (https://dart.dev/interop/java-interop). No MethodChannel is used for the generated API surface. The Flutter example uses `package:jni_flutter` solely to obtain the Android application `Context`/`Activity` — a platform-integration need, isolated in the example.
- Flutter and Dart are trademarks of Google LLC; this project is not affiliated with or endorsed by the Flutter/Dart teams.
