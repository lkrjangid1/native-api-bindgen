# Android support

## What is read

| Input | Used for |
|---|---|
| `platforms/android-N/android.jar` | classes, members, JVM descriptors, generic signatures, modifiers, constants, inheritance, class-file annotations, parameter names (`LocalVariableTable`/`MethodParameters`) |
| `platforms/android-N/data/api-versions.xml` | introduced / deprecated / removed API levels (including minor levels such as 36.1); ancestor-aware so overrides inherit availability |
| `platforms/android-N/data/annotations.zip` | external annotations (`IntDef`, `RequiresPermission`, threading, ranges, …) |

## Supported in this version

- Classes, interfaces, enums, nested (static and inner) types
- Constructors, static/instance methods, overloads, varargs, fields, compile-time constants (exact values)
- Nullability from `android.annotation`/`androidx.annotation` (incl. `Recently*`)
- Availability with runtime guards for APIs newer than `minApi`
- Threading and permission metadata in generated docs
- Implementing Java interfaces in Dart (callbacks/listeners)
- Java exceptions surfaced as `NativeJavaException`

## Not yet supported (reported with reason codes)

| Construct | Code | Notes |
|---|---|---|
| Protected members | E002 | require subclassing Java classes from Dart |
| Constructors of abstract classes | E002 | |
| Annotation interfaces | E002 | metadata, not callable |
| Generic type parameters on generated types | E003 | erased to bounds; values still usable |
| Types outside the selected closure | E016 | exposed as `JObject`; add with `--entry` |
| Kotlin-specific constructs (suspend, Flow, properties, default args) | — | android.jar is Java; Kotlin metadata parsing is planned |
| Native UI (embedding Android `View`s) | — | separate integration layer planned |

## Hidden / non-SDK APIs

`android.jar` contains only public SDK stubs. A class absent from `api-versions.xml` is classified `hidden_or_non_sdk` (E006) and never generated, and the same applies to its members. Members present in public stubs but not listed (in practice: re-declared from a non-public superclass) are generated with `partial` support and an `E012` note because their availability is inferred, not listed.

## Measured on android-36 (this machine, see `docs/benchmarks`)

- Parse entire android.jar: 6,222 types in ~0.6 s
- Generate Flutter bindings for every package: 6,196 types, 95,888 members, 1,135,260 lines; `dart analyze` reports no issues
