# React Native (Android)

> Experimental. New Architecture only (TurboModules/JSI). iOS is not implemented yet (`E015`).

`native-api-bindgen generate react-native` writes a self-contained bindings library (default `native-api-bindings/`) into your app:

| Path | Contents |
|---|---|
| `src/generated/<package>.ts` (+ `index.ts`) | one TypeScript module per Java package, one class per Java type (constructors as `X.new…()`, static/instance methods, `…Async()` Promise variants, constants, fields, `X.implement({...})` for interfaces) |
| `cpp/generated/NabBindings.cpp` | constant member tables (Java name + JNI descriptor) — no per-API C++ code |
| `cpp/runtime/`, `src/runtime.ts`, `android/java/…` | the runtime (copied, Apache-2.0) |
| `specs/NativeApiBindgen.ts` | Codegen spec of the single pure C++ Turbo Module that installs `global.__nab` |
| `native-api-bindings.cmake`, `android/proguard-rules.pro` | build integration |

One-time app integration is described in the generated `README.md` (codegenConfig, CMake + `OnLoad.cpp` per reactnative.dev "pure C++ modules", Gradle source set, `NabContext.init(this)`). `examples/react-native/android_slice` is a complete working app.

## Usage

```ts
import {Intent, Uri, Handler, Looper, Runnable, applicationContext, currentActivity} from './native-api-bindings';

applicationContext().getPackageName();                      // sync JSI → JNI call
const intent = Intent.new$String$Uri(Intent.ACTION_VIEW, Uri.parse('https://example.com'));
currentActivity()?.startActivity(intent);

const uri = await Uri.parseAsync('content://x/y');           // JNI call on a background thread

Handler.new$Looper(Looper.getMainLooper()!)                  // callbacks from Java threads
  .post(Runnable.implement({run: () => console.log('ran')}, {async: ['run']}));
```

## Semantics

- **Types** (`generation.typescriptMode`): `strict-typescript` (default) maps Java `long` to `bigint`; `ergonomic-typescript` maps it to `number` and flags constants beyond ±2^53 (`E011`). `String` ↔ `string`, primitive arrays ↔ `number[]`/`boolean[]` (copied), object arrays ↔ arrays of wrappers.
- **Nominal typing**: parameters typed as a Java class/interface accept any wrapper whose Java type is that class or a subtype (brand types). Use `obj.as(Cls)` for checked casts and `obj.isInstanceOf(Cls)`.
- **Objects**: each wrapper owns a JNI global reference held by a JSI HostObject — released when JS garbage-collects it or explicitly via `release()`/`dispose()`. Use after release throws `UseAfterReleaseError`.
- **Errors**: Java exceptions throw `NativeJavaError` (`nativeClassName`, `javaStackTrace`); SDK-declared non-null results that are null throw `NativeNullError`; APIs newer than `minApi` are guarded (`NativeApiUnavailableError`, `E012`).
- **Callbacks**: on the JS thread they run synchronously. From other Java threads, `void` methods listed in `options.async` return to Java immediately; other calls block the Java thread until JS answers (deadlocks if JS is itself blocked waiting on that thread). A throwing `void` callback is reported (`NativeCallbacks.onError`, `ErrorUtils`) and does not crash; non-void callbacks propagate as a Java `RuntimeException`.
- **Context/Activity**: `NabContext.init(application)` (public SDK APIs only) backs `applicationContext()`/`currentActivity()`.

## Size

Metro does not tree-shake, so all generated TypeScript ships in the bundle: generate only what you need (`entries`/`depth`). Measured numbers: `docs/benchmarks/size.md`.
