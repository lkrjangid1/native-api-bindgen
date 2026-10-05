# Android support

## What is read

| Input | Used for |
|---|---|
| `platforms/android-N/android.jar` | classes, members, JVM descriptors, generic signatures, modifiers, constants, inheritance, class-file annotations, parameter names (`LocalVariableTable`/`MethodParameters`) |
| `platforms/android-N/data/api-versions.xml` | introduced / deprecated / removed API levels (including minor levels such as 36.1); ancestor-aware so overrides inherit availability |
| `platforms/android-N/data/annotations.zip` | external annotations (`IntDef`, `RequiresPermission`, threading, ranges, …) |
| `platform.android.libraries` / `--jar` | optional library artifacts (`.jar`, `.aar`, class directories), e.g. a Kotlin library; their classes are library APIs (no `api-versions.xml` classification, no platform doc links) |

## Supported in this version

- Classes, interfaces, enums, nested (static and inner) types
- Constructors, static/instance methods, overloads, varargs, fields, compile-time constants (exact values)
- Nullability from `android.annotation`/`androidx.annotation` (incl. `Recently*`)
- Availability with runtime guards for APIs newer than `minApi`
- Threading and permission metadata in generated docs
- Implementing Java interfaces in Dart (callbacks/listeners)
- Java exceptions surfaced as `NativeJavaException`
- Generics (Flutter): generated types and methods take Dart type parameters (`GenericClass<$T>`, `first<$E>(…)`), parameterized types keep their arguments (`JList<JString?>`), results are cast for free (every wrapper is a `JObject` at run time); supertypes stay raw. `java.util.List/Map/Set/Collection/Iterator` and boxed numbers map to `package:jni`'s wrappers when not generated. On android-36 this removed all 2,384 `E003` notes of the Flutter target.
- Bean properties (Flutter and React Native): `getX()`/`isX()` plus a matching `void setX(T)` also generate a property `x` backed by the native getter/setter (`uri.scheme`, `intent.data`, `paint.underlineText = true`). The methods stay; a property is skipped when its name is already a member or a type name, and it is read-only when the setter's type differs from the getter's. android-36: 12,513 properties (Flutter), 11,886 (React Native).
- Typed constants (Flutter and React Native): `@IntDef`/`@LongDef`/`@StringDef` from `annotations.zip` become a typed set per owner, named from the constants' shared prefix (`Intent.FLAG_*` → `Intent$Flag`, `Context.*_SERVICE` → `Context$Service`). Sets with the same name in one owner are merged (union). Dart: a `const` extension type that implements `int`/`String` (flag sets add `|` and `has`), so values pass wherever the API takes the raw type. TypeScript: an `as const` object plus a union type (non-flag sets). Parameters keep the raw type in every mode; in `ergonomic-dart` / `ergonomic-typescript`, results are typed with the set. Values are the SDK constants, never altered. android-36: 851 sets over 2,109 use sites; 467 use sites stay documented only (constants from several owners or outside the selection, or no shared name).
- Kotlin `suspend` functions: detected from the compiled JVM signature (trailing `kotlin.coroutines.Continuation<? super T>`). Flutter: `Future<T>` over `package:jni`'s `PortContinuation`. React Native: `Promise<T>` over the runtime's `NabContinuation` (a reflective `Continuation` proxy; the promise settles on the JS thread through `CallInvoker`). Boxed results are unboxed (`Int` → `int` / `number`), `Unit` → `void`, Kotlin exceptions → `NativeJavaException` / `NativeJavaError`. The app needs `kotlinx-coroutines-android` at run time.
- `kotlin.Metadata` (pure-Dart, bounded protobuf reader; fuzz-tested): suspend results are non-null when Kotlin declares them so (`Future<String>` vs `Future<String?>`); type-argument nullability (`Flow<String?>`, `List<Int>`); nullability of unannotated members; Kotlin parameter names when the class file has none; default arguments are reported (`E002` info: pass every argument). Kotlin properties surface through their accessors as bean properties. Validated on kotlin-stdlib 2.4.20 (7,450 of 7,567 functions matched to class-file methods; the rest are annotation-class constructors and a few `KFunction` signatures) and kotlinx-coroutines-core 1.10.2 (1,930 of 1,945).
- Kotlin `Flow<T>` (Flutter): generated as `Stream<T>`; collection starts on `listen` (a Dart `FlowCollector`), errors arrive as stream errors, cancelling the subscription aborts the flow at its next `emit`. Values are buffered (no backpressure). React Native exposes `Flow` as an opaque `JavaObject` for now.

## Not yet supported (reported with reason codes)

| Construct | Code | Notes |
|---|---|---|
| Protected members | E002 | require subclassing Java classes from Dart |
| Constructors of abstract classes | E002 | |
| Annotation interfaces | E002 | metadata, not callable |
| Generic type parameters (React Native only) | E003 | TypeScript erases them to bounds; the Flutter target generates Dart type parameters (Java bounds are documented, not repeated) |
| Types outside the selected closure | E016 | exposed as `JObject`; add with `--entry` |
| Kotlin default arguments | E002 (info) | not applied through JNI; pass every argument (or use `@JvmOverloads` overloads) |
| Kotlin `Flow` on React Native | E016 | exposed as an opaque `JavaObject` (Flutter: `Stream`) |
| Native UI (embedding Android `View`s) | — | separate integration layer planned |

## Hidden / non-SDK APIs

`android.jar` contains only public SDK stubs. A class absent from `api-versions.xml` is classified `hidden_or_non_sdk` (E006) and never generated, and the same applies to its members. Members present in public stubs but not listed (in practice: re-declared from a non-public superclass) are generated with `partial` support and an `E012` note because their availability is inferred, not listed.

## Measured on android-36 (this machine, see `docs/benchmarks`)

- Parse entire android.jar: 6,222 types in ~0.6 s
- Generate Flutter bindings for every package: 6,196 types, 95,888 members, 1,135,260 lines; `dart analyze` reports no issues
- Whole-SDK generation (compiled CLI, `/usr/bin/time -l`, 2026-10-05): 6,197 types, 95,922 members bound in 3.4 s wall time; peak resident memory 415,694,848 bytes (was 1,079,951,360 before the IR and binding map were written as streams; output byte-identical)
