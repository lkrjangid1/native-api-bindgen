# React Native

> Experimental. New Architecture only (TurboModules/JSI). Android (Java APIs) and iOS (Objective-C APIs) share one bindings library and one pure C++ Turbo Module.

`native-api-bindgen generate react-native` writes a self-contained bindings library (default `native-api-bindings/`) into your app for every configured platform (`react-native-android` / `react-native-ios` select one). iOS generation needs macOS with Xcode; elsewhere it is skipped with a warning.

## Android

| Path | Contents |
|---|---|
| `src/generated/<package>.ts` (+ `index.ts`) | one TypeScript module per Java package, one class per Java type (constructors as `X.new…()`, static/instance methods, `…Async()` Promise variants, constants, fields, `X.implement({...})` for interfaces) |
| `cpp/generated/NabBindings.cpp` | constant member tables (Java name + JNI descriptor) — no per-API C++ code |
| `cpp/runtime/`, `src/runtime.ts`, `android/java/…` | the runtime (copied, Apache-2.0) |
| `specs/NativeApiBindgen.ts` | Codegen spec of the single pure C++ Turbo Module that installs `global.__nab` |
| `native-api-bindings.cmake`, `android/proguard-rules.pro` | build integration |

One-time app integration is described in the generated `README.md` (codegenConfig, CMake + `OnLoad.cpp` per reactnative.dev "pure C++ modules", Gradle source set, `NabContext.init(this)`). `examples/react-native/slice` is a complete working app.

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

## iOS

`generate react-native-ios` adds to the same library:

| Path | Contents |
|---|---|
| `src/generated/apple/<module>.ts`, `ios.ts` | one TypeScript class per Objective-C class/protocol (`X.alloc()`, `X.new$()`, `init…` methods, properties as accessors, `…Async()` Promise variants, `X.isA()` / `P.conformsTo()`), interfaces for structs, `as const` objects for enums |
| `cpp/generated/NabBindingsObjC.cpp` | member tables: selector + JS conversion codes + flags, struct field names |
| `cpp/runtime-objc/`, `src/runtime-objc.ts` | the Objective-C++ runtime (copied, Apache-2.0) |
| `NativeApiBindings.podspec` | CocoaPods integration (links the configured frameworks) |

One-time app integration: `pod 'NativeApiBindings', :path => '../native-api-bindings'` in `ios/Podfile`, and `"ios": {"modulesProvider": {"NativeApiBindgen": "NabModuleProvider"}}` in `package.json` `codegenConfig`. Import from `'<library>/ios'`.

```ts
import {UIDevice, UIView, NSFileManager, isNativeObjCError} from './native-api-bindings/ios';

UIDevice.currentDevice.systemName;                           // 'iOS' — UIKit call, run on the main thread
const view = UIView.alloc().initWithFrame({origin: {x: 0, y: 0}, size: {width: 10, height: 10}});
view.tag = 42n;                                              // NSInteger is bigint in strict-typescript
await NSFileManager.defaultManager.fileExistsAtPathAsync('/'); // Foundation call on a background queue
try {
  NSFileManager.defaultManager.contentsOfDirectoryAtPath('/missing');
} catch (e) {
  if (isNativeObjCError(e)) console.log(e.domain, e.code); // NSError ** → NativeObjCError
}
```

- **Calls** go through `NSInvocation` with the method signature reported by the Objective-C runtime, so argument layouts are never guessed. Members declared in UIKit run on the main thread (synchronously from the JS thread; `…Async()` variants dispatch asynchronously). Other members run on the calling thread, or a background queue for `…Async()`.
- **Values**: `NSString` ↔ `string`; `BOOL` ↔ `boolean`; `NSInteger`/`NSUInteger`/64-bit enums ↔ `bigint` (strict) or `number` (ergonomic); structs ↔ plain objects (also anonymous structs such as `NSOperatingSystemVersion`); objects ↔ wrapper classes (`nil` ↔ `null`).
- **Objects**: each wrapper holds a strong reference in a JSI HostObject; the final release is sent to the main thread (UIKit objects must deallocate there). `release()`/`dispose()`, `UseAfterReleaseError`, `DoubleReleaseError` behave as on Android.
- **Errors**: `NSError **` (last parameter) is hidden and a failure throws `NativeObjCError` (`domain`, `code`); an Objective-C exception throws `NativeObjCException` (`exceptionName`, `reason`); APIs newer than `platform.ios.minVersion` throw `NativeApiUnavailableError` (`E012`).
- **Not supported yet**: blocks and implementing protocols in JS (`E004`), raw C pointers, `SEL`/`Class` parameters, structs with non-numeric fields (`E002`). Class methods are available on the declaring class only.

## Size

Metro does not tree-shake, so all generated TypeScript ships in the bundle: generate only what you need (`entries`/`depth`). Measured numbers: `docs/benchmarks/size.md`.
