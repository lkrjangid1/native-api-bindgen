# Architecture overview

## Principle

The **Native IR** is the single source of truth. Parsers produce IR; generators consume IR. No generator reads SDK files or documentation directly, and documentation is never a source of signatures.

```
 Platform SDK artifacts            Official metadata               Official annotations
 (android.jar class files)   (api-versions.xml availability)   (class-file + annotations.zip)
            └───────────────────────────┬───────────────────────────────┘
                                        ↓
                         Platform parser  (native_api_android)
                                        ↓
                         Canonical Native IR  (native_api_ir)
                                        ↓
         Validation · normalization · dependency graph · type mapping  (native_api_generator)
                     ┌──────────────────┴───────────────────┐
              Flutter target                         React Native target (planned)
      native_api_flutter_android                native_api_react_native_android
       Dart + package:jni (JNI)                    TS + C++/JSI + JNI
                     └──────────────────┬───────────────────┘
                                 Native platform
```

## Packages

| Package | Responsibility | Depends on |
|---|---|---|
| `native_api_ir` | IR data model, stable symbol IDs, canonical JSON, validation, diagnostic codes | — |
| `native_api_core` | project info/versions, configuration, structured logging, path guard, license audit, dependency graph, IR diff | ir |
| `native_api_android` | Android SDK discovery, zip + JVM class-file + generic-signature parsers, api-versions/annotations enrichment, IR construction | ir, core |
| `native_api_generator` | target-independent generation services: type mapping, identifier escaping, overload naming, deterministic file writer, binding map | ir, core |
| `native_api_flutter_android` | emits Dart extension types over `package:jni` | ir, core, generator |
| `native_api_cli` (pub name `native_api_bindgen`) | command line: wiring only, no business logic | all of the above |
| `runtimes/dart/native_api_runtime` | small runtime used by generated code: availability guard, error model, handle helpers | `package:jni` |
| `native_api_ios`, `native_api_flutter_ios`, `native_api_react_native_*` | placeholders; CLI reports `not yet implemented` diagnostics | — |

Dependencies point downward only (enforced by pubspec). Parsers do not know generators exist; generators do not know where IR came from.

## Data flow for `generate flutter --entry android.content.Intent`

1. `AndroidSdkLocator` resolves the SDK (ANDROID_HOME → ANDROID_SDK_ROOT → OS default) and platform (`platform.android.sdk` or highest stable).
2. `AndroidJarReader` lists class entries; `ClassFileParser` parses only requested classes on demand (lazy, bounded).
3. `ApiVersionsIndex` and `AnnotationsIndex` attach availability, nullability, threading, permissions, IntDef.
4. `DependencyGraph` computes the closure from the entry symbol up to the configured depth. Types outside the closure are **opaque**: they map to `JObject` and get a diagnostic note, they are never silently pulled in.
5. `IrValidator` checks invariants (unique IDs, resolvable references, no hidden API marked public).
6. `DartJniEmitter` generates one Dart library per Java package plus an umbrella library; `GeneratedFileWriter` writes through the path guard and records a `binding_map.json` (generated symbol → native symbol).
7. `coverage.json` and `ir.json` are written next to the output for `coverage`, `why-generated`, `why-skipped`.

## Generated-code shape (Flutter Android)

Each Java class becomes a Dart **extension type** over `JObject`. Extension types are zero-cost wrappers and are tree-shakable: there is no registry, no reflection and no startup registration, so unused classes and members are removed by the Dart AOT compiler. Method IDs are `static final` lazily-initialised fields, resolved on first use only.

See also: [ir.md](ir.md), [type-mapping.md](type-mapping.md), [lifecycle.md](lifecycle.md).
