# Roadmap

Items below are **plans**, not features. Completed items are marked with the release that shipped them.

- **Phase 1 — Android Java API generation (Flutter).** Vertical slice working in 0.1.0-dev.1 (unreleased): Intent, Uri, Bundle, Context, Activity, Handler, Looper, Runnable/Handler.Callback callbacks verified on an Android emulator. Whole-SDK generation compiles (android-36) but only the slice is runtime-tested.
- **Phase 2 — Android callbacks/generics/annotations at scale.** Partial: annotations and erasure-based generics in the slice. Planned: generic type parameters on generated types, IntDef enums, Kotlin metadata (suspend → Future, Flow).
- **Phase 3 — Objective-C / iOS.** Flutter vertical slice working (unreleased): Xcode SDK discovery, libclang extraction, Dart over `package:objective_c`; Foundation/UIKit APIs verified on an iOS 26.4 simulator (12 tests). Planned: blocks and Dart-implemented protocols (native trampolines via a build hook), React Native iOS.
- **Phase 4 — Flutter production runtime.** Planned: callback threading policy, size/perf benchmarks, sharded packages.
- **Phase 5 — React Native New Architecture.** Android vertical slice working (unreleased): TypeScript + one pure C++ Turbo Module + JSI HostObjects + JNI, verified on an emulator (12 self-tests). iOS (ObjC++) planned.
- **Phase 6 — Swift-only API adapters.** Planned, conservative.
- **Phase 7 — Native UI integration layer.** Planned.
- **Website (GitHub Pages).** Planned after the first vertical slices.

Tracked limitations of the current version are listed in `docs/compatibility/matrix.md`.
