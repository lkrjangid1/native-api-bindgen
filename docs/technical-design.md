# Technical design (stage 1)

Status: living document. Scope: foundation + Android → Flutter vertical slice.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | Generator core and CLI written in **Dart** (pub workspace) | Same ecosystem as `package:jni`/`ffigen`; distribution via `dart pub global activate`; no extra runtime for Flutter users. |
| D2 | Android signatures read by a **pure-Dart JVM class-file parser** over `android.jar` | Machine-readable, first-party, offline, deterministic. No JVM required to generate. HTML documentation is never parsed. |
| D3 | Availability from `platforms/android-N/data/api-versions.xml`; external annotations from `data/annotations.zip`; nullability from class-file `Runtime(In)VisibleAnnotations` | All shipped inside the official SDK platform package. |
| D4 | Flutter Android output = Dart **extension types over `package:jni` `JObject`** using the public `JClass` / method-ID API; interface implementation uses `JImplementer` (the mechanism `package:jni` provides for jnigen) | Officially recommended Dart↔Java interop path; no MethodChannel; zero-cost wrappers; tree-shakable. |
| D5 | We do not invoke `jnigen`; our own emitter consumes our IR | The IR must remain the single source of truth for all targets (Flutter and React Native). |
| D6 | Overloads → deterministic names: the first overload in canonical order keeps the Java name, later ones get `$1`, `$2`…; constructors are `new$`, `new$1`, … ; mapping is recorded in `binding_map.json` and the doc comment | Same scheme as jnigen output, familiar to Dart JNI users; stable across runs because canonical order is by JVM descriptor. |
| D7 | Default distribution policy `local-only`, documentation mode `links-only` | Safest legal default; see `docs/legal`. |
| D8 | Threading defaults to `unspecified` | Never claim thread-safety without metadata. |
| D10 | React Native: one pure C++ Turbo Module installs `global.__nab`; generated C++ is *data* (member tables keyed by Java name + JNI descriptor) interpreted by one runtime | Official New Architecture mechanism (reactnative.dev pure C++ modules); no per-API TurboModule/Codegen surface; small, uniform C++ |
| D11 | React Native TS output is a single module without `extends` between generated classes; inherited members are copied onto prototypes (`$rt.inherit`) and typed via declaration merging; parameters use brand types | Avoids ES-module cycle initialisation failures under Metro and TypeScript override/static-side conflicts; keeps output linear in API size (full android-36: 187 MB → 98 MB) |
| D12 | RN callbacks via `java.lang.reflect.Proxy` + `CallInvoker`; context via `NabContext.init(app)` | Public SDK APIs only (no hidden `ActivityThread`) |
| D9 | Apache-2.0 for project source | Permissive with explicit patent grant. This is a project/legal decision the owner may revisit. |

## IR

See `architecture/ir.md`. Key properties: stable symbol IDs (`android.content.Intent#setData(android.net.Uri)`), canonical JSON (sorted keys, sorted members), provenance on every type, support status + reason code on every excluded symbol.

## Android parsing

- Zip reading is lazy: the central directory is indexed; class bytes are inflated only for classes in the requested closure (`android.jar` has ~6k classes; the slice needs tens).
- Class-file parser: magic/version check, constant pool (all tags incl. dynamic/module), access flags, this/super/interfaces, fields, methods, attributes `Signature`, `Exceptions`, `InnerClasses`, `ConstantValue`, `Deprecated`, `RuntimeVisibleAnnotations`, `RuntimeInvisibleAnnotations`, `RuntimeInvisibleParameterAnnotations`, `MethodParameters`. Every read is bounds-checked; limits: 64 MiB per class, 65535 cp entries, annotation nesting depth 32.
- Generic signatures parsed per JVMS §4.7.9.1 (class, method, field signatures; wildcards; type variables; inner-class suffixes).
- Visibility: only `public`/`protected` members of `public` classes are API. Synthetic/bridge members are excluded with reason `E002`-family notes. Symbols present in `android.jar` but absent from `api-versions.xml` are flagged `hidden_or_non_sdk` (they are stubs not part of the published API list) and never emitted.

## Flutter Android generation

- One library per Java package (`android/content.dart`), umbrella `android.dart`.
- Each class: `extension type Intent._(JObject _$this) implements Object$` (superclass chain and interfaces are `implements` clauses when generated; otherwise `JObject`).
- Members: constructors (`factory`), static/instance methods, static/instance fields (getter/setter), compile-time constants inlined from `ConstantValue` with the exact value.
- Primitive return/param mapping via the shared `TypeMapper`; Java `int`/`short`/`byte`/`char`/`float` are passed with `JValueInt` etc. so JNI receives exact widths.
- Nullability: `@NonNull`/`@RecentlyNonNull` → non-nullable Dart type; `@Nullable` → `T?`; unknown → `T?` (safe default) with `nullability: unknown` in IR.
- Availability: if `introduced > minApi`, a guard `NativeApi.requireAndroidApi(n, symbol)` is emitted that throws `NativeApiUnavailableException` (E012) on older devices instead of crashing in JNI.
- Exceptions: Java exceptions surface as `package:jni` `JThrowable`; the runtime converts them to `NativeJavaException` (class name, message, Java stack trace, original throwable) via `NativeApi.guard`.
- Callbacks: Java interfaces whose methods all map get `implement(...)` factories built on `JImplementer`; the Dart handler is retained until the Java proxy is garbage-collected (port closed by `package:jni`).

## Out of scope (stage 1)

React Native, iOS/Objective-C/Swift, Kotlin metadata (suspend/Flow), native UI integration layer, website. The CLI returns explicit diagnostics for these.
