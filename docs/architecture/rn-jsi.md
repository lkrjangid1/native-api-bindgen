# React Native target: TypeScript → JSI → C++ → JNI

```
src/generated/<package>.ts             one TS module per Java package; members call
   Intent.$t()['setData(android.net.Uri)Landroid/content/Intent;'](async, self, ...args)
        │  classTable(): lazily resolves global.__nab['android.content.Intent']
        ▼
global.__nab  (JSI HostObject, installed by the NativeApiBindgen pure C++ Turbo Module)
        │  first access → lookupClass() binary search in NabBindings.cpp → host functions
        ▼
NabRuntime.cpp   converts JS ↔ JNI per JNI descriptor, caches jclass/jmethodID per member,
                 maps Java exceptions to JS errors, runs async calls on worker threads and
                 settles Promises via CallInvoker
        ▼
JNI → Android framework
```

Design choices (see `docs/technical-design.md` for the decision log):

- **Data, not code, in C++.** Generated C++ is a sorted table of `{key, javaName, descriptor, kind}`. One runtime handles every member, so C++ output is small and cannot drift from the runtime. Keys are Java name + descriptor: stable and unique.
- **One module per Java package, no `extends` between generated classes.** Each class emits only its declared members and lists its ancestors in a `static $anc = () => [...]` thunk; the runtime copies inherited members onto the prototype the first time the class is instantiated (`ensureInherited`). Because nothing touches another module at load time, import cycles between packages are harmless, and Metro can transform modules independently (a single 98 MB module exhausted Metro's 4 GB heap). Inherited members are typed via class/interface declaration merging. Overrides keep the ancestor's member name; names that collide across multiple supertypes are resolved per class and forwarded explicitly.
- **Callbacks** use `java.lang.reflect.Proxy` with a Java `InvocationHandler` (`NabInvocationHandler`) whose native method dispatches to the JS implementation on the JS thread through `CallInvoker`. The JS implementation is released when the Java proxy is finalized (on the JS thread).
- **Threading**: JSI values are only touched on the JS thread; worker threads only see JNI global references.

Measured: full android-36 SDK (6,196 types) generates 283 modules / 97.7 MB of TypeScript (largest: `android/widget.ts`, 11.1 MB) that type-check with zero errors and 9.4 MB of C++ tables that compile with `-Wall -Wextra -Werror`.
