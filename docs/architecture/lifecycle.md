# Native object lifecycle, callbacks and threading

<!-- seo-title: Object lifecycle, callbacks and threading -->
<!-- description: How generated bindings own native objects, release them, implement Java callbacks in Dart, and handle threads and API-level availability. -->

## Ownership

Every generated object is a `package:jni` **global reference** wrapped in a zero-cost extension type.

- Released automatically by a native finalizer when the Dart object is garbage-collected.
- Can be released early and explicitly with `release()`; `dispose()` (from `native_api_runtime`) is the idempotent variant.
- Use after release throws `UseAfterReleaseError`; double `release()` throws `DoubleReleaseError`.
- Object identity/equality: `==` and `hashCode` delegate to Java `equals`/`hashCode` (inherited from `JObject`).

Measured in tests: 10,000 create/release cycles on a host JVM and on an Android emulator without leaks or crashes.

## Callbacks (Java interfaces implemented in Dart)

`X.implement($X(...))` builds a Java proxy via `package:jni`'s `JImplementer`. The Dart implementation is retained until the Java proxy is garbage-collected (`package:jni` closes the port), so callbacks after Dart-side disposal cannot reach freed Dart objects.

- Calls on the Dart isolate's thread are dispatched synchronously.
- Calls from other Java threads are posted to the isolate. By default the Java thread **waits** for the result; set `<method>$async: true` for `void` methods to return immediately. A Java thread that blocks while the Dart isolate itself is blocked waiting on that thread deadlocks — use `$async` for fire-and-forget listeners called from background threads.
- Errors: a `void` callback that throws is reported through `NativeCallbacks.onError` and the current zone's uncaught-error handler and returns normally to Java (policy `reportVoidCallbacks`, default), so a Dart bug cannot kill the main Looper. Non-void callbacks propagate the error to Java as an exception.

## Threading

Threading metadata comes from official annotations only (`@MainThread`, `@UiThread`, `@WorkerThread`, `@AnyThread`) and is shown in generated docs. Absence of metadata is `unspecified`, never "thread-safe". Generated calls run on the calling Dart thread; the generator does not hop threads implicitly.

## Availability

Members newer than `minApi` get a runtime guard: `AndroidApi.require(major, minor, symbol)` throws `NativeApiUnavailableException` (E012) before any JNI lookup. Minor SDK versions (e.g. 36.1) use `Build.VERSION.SDK_INT_FULL` on API 36+.
