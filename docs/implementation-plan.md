# Implementation plan

Mirrors TRD §82. Each stage ends with: format → analyze → unit tests → generation tests → integration tests (where available) → inspect generated output → size check → docs/compatibility update.

| Stage | Content | Status |
|---|---|---|
| A Foundation | monorepo, IR, config, diagnostics, logging, versions, CLI, legal/source docs | done (0.1.0-dev.1) |
| B Android | SDK detection, class-file parsing, IR, Java/JNI mapping, Dart generation, runtime, tests | vertical slice done: on-device integration tests pass |
| C Android advanced | annotations, generics, callbacks, lifecycle, threading, async, permissions, coverage | partial (annotations, generics-erasure, callbacks, coverage); Kotlin suspend/Flow not started |
| D Apple | Xcode detection, Objective-C via Clang AST, IR, Dart bindings via `package:objective_c` | not started |
| E Swift | layered Swift support | not started |
| F React Native | TS + Codegen specs + C++/JSI + JNI/ObjC++ | not started |
| G Distribution | packages, release, examples | not started |
| H Website | static GitHub Pages site, SEO | not started |

Vertical-slice order (TRD §83/§113): Android→Flutter first (done), then Android→React Native (next), then iOS.
