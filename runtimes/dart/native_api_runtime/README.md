# native_api_runtime

Small runtime used by Dart code that native-api-bindgen generates for Android (over `package:jni`):

- `AndroidApi` — `SDK_INT` / minor-version checks behind generated availability guards (`NativeApiUnavailableException`, E012).
- `guardJni` / `NativeJavaException` — Java exceptions with class name, message and stack trace.
- `NativeCallbacks` — error policy for Dart implementations of Java interfaces.
- `callSuspend` — Kotlin `suspend` functions as Dart `Future`s (through `package:jni`'s continuation support).

It holds no registry of generated types and does no work at startup. Generated iOS bindings use `package:objective_c` directly plus a generated `apple/_runtime.dart`.
