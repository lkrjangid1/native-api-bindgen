# React Native target: TypeScript → JSI → C++ → JNI

```
bindings.ts (generated)                 one TS class per Java type; members call
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
- **Single TS module, no `extends` between generated classes.** ES-module cycles between per-package files would break class initialisation under Metro. Each class emits only its declared members; inherited ones are copied onto the prototype at load (`$rt.inherit`) and typed via class/interface declaration merging. Overrides keep the ancestor's member name; names that collide across multiple supertypes are resolved per class and forwarded explicitly.
- **Callbacks** use `java.lang.reflect.Proxy` with a Java `InvocationHandler` (`NabInvocationHandler`) whose native method dispatches to the JS implementation on the JS thread through `CallInvoker`. The JS implementation is released when the Java proxy is finalized (on the JS thread).
- **Threading**: JSI values are only touched on the JS thread; worker threads only see JNI global references.

Measured: full android-36 SDK (6,196 types) generates 98 MB of TypeScript that type-checks with zero errors and 9.4 MB of C++ tables that compile with `-Wall -Wextra -Werror`.
