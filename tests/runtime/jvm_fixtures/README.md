# Host-JVM runtime tests for generated bindings

Generated bindings for `fixtures/java/basic` are executed against a real JVM
(desktop `package:jni`). This proves generated calls, overload dispatch,
nullability, exceptions, callbacks (same thread and foreign Java threads),
callback error policy and handle lifecycle without an Android device.

Run with `tools/run_jvm_runtime_tests.sh` (builds the `package:jni` native
helper once, regenerates bindings with the CLI, compiles fixtures, runs tests).
