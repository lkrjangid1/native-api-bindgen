// native-api-bindgen React Native runtime. Apache License, Version 2.0.
package dev.nativeapibindgen.runtime;

import java.lang.reflect.Field;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/**
 * A {@code kotlin.coroutines.Continuation} for calling Kotlin {@code suspend}
 * functions from JavaScript. Native code passes one as the last argument; when
 * the function suspends, {@code resumeWith} settles the JavaScript promise
 * through native code. Built with {@link Proxy} and reflection so the runtime
 * has no compile-time dependency on the Kotlin standard library (it is only
 * loaded when a suspend function is called, so it exists at run time).
 */
public final class NabContinuation implements InvocationHandler {
  private static volatile Object emptyContext;
  private static volatile Class<?> failureClass;
  private static volatile Field failureException;

  private final long id;

  private NabContinuation(long id) {
    this.id = id;
  }

  /** Creates a continuation for pending call {@code id}. Called from native code. */
  public static Object create(long id) throws ReflectiveOperationException {
    ClassLoader loader = NabContinuation.class.getClassLoader();
    Class<?> continuation = Class.forName("kotlin.coroutines.Continuation", false, loader);
    if (emptyContext == null) {
      emptyContext = Class.forName("kotlin.coroutines.EmptyCoroutineContext", true, loader)
          .getField("INSTANCE")
          .get(null);
      Class<?> failure = Class.forName("kotlin.Result$Failure", true, loader);
      failureException = failure.getField("exception");
      failureClass = failure;
    }
    return Proxy.newProxyInstance(loader, new Class<?>[] {continuation}, new NabContinuation(id));
  }

  /** Whether {@code result} is {@code COROUTINE_SUSPENDED}. Called from native code. */
  public static boolean isSuspended(Object result) {
    return result != null
        && result.getClass().getName().equals("kotlin.coroutines.intrinsics.CoroutineSingletons")
        && "COROUTINE_SUSPENDED".equals(result.toString());
  }

  @Override
  public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
    switch (method.getName()) {
      case "getContext":
        return emptyContext;
      case "resumeWith":
        Object result = args[0];
        if (result != null && result.getClass() == failureClass) {
          fail0(id, (Throwable) failureException.get(result));
        } else {
          resume0(id, result);
        }
        return null;
      case "equals":
        return proxy == args[0];
      case "hashCode":
        return System.identityHashCode(proxy);
      case "toString":
        return "NabContinuation@" + id;
      default:
        throw new UnsupportedOperationException(method.getName());
    }
  }

  private static native void resume0(long id, Object value);

  private static native void fail0(long id, Throwable error);
}
