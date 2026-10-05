// native-api-bindgen React Native runtime. Apache License, Version 2.0.
package dev.nativeapibindgen.runtime;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/**
 * Java side of interfaces implemented in JavaScript. Each proxy forwards calls
 * to native code, which dispatches them to the JS implementation on the JS
 * thread. The JS implementation is released when this handler is finalized.
 */
public final class NabInvocationHandler implements InvocationHandler {
  private final long id;

  private NabInvocationHandler(long id) {
    this.id = id;
  }

  /** Creates a proxy implementing {@code iface}. Called from native code. */
  public static Object create(long id, Class<?> iface) {
    return Proxy.newProxyInstance(
        NabInvocationHandler.class.getClassLoader(),
        new Class<?>[] {iface},
        new NabInvocationHandler(id));
  }

  @Override
  public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
    if (method.getDeclaringClass() == Object.class) {
      switch (method.getName()) {
        case "equals":
          return proxy == args[0];
        case "hashCode":
          return System.identityHashCode(proxy);
        case "toString":
          return method.getDeclaringClass().getName() + "$NabProxy@" + Integer.toHexString(System.identityHashCode(proxy));
        default:
          break;
      }
    }
    return invoke0(id, method.getName() + descriptor(method), args, method.getReturnType() == void.class);
  }

  @Override
  @SuppressWarnings({"deprecation", "removal"})
  protected void finalize() throws Throwable {
    try {
      release0(id);
    } finally {
      super.finalize();
    }
  }

  static String descriptor(Method m) {
    StringBuilder b = new StringBuilder("(");
    for (Class<?> p : m.getParameterTypes()) {
      b.append(descriptor(p));
    }
    return b.append(')').append(descriptor(m.getReturnType())).toString();
  }

  static String descriptor(Class<?> c) {
    if (c.isArray()) return c.getName().replace('.', '/');
    if (c == void.class) return "V";
    if (c == boolean.class) return "Z";
    if (c == byte.class) return "B";
    if (c == char.class) return "C";
    if (c == short.class) return "S";
    if (c == int.class) return "I";
    if (c == long.class) return "J";
    if (c == float.class) return "F";
    if (c == double.class) return "D";
    return "L" + c.getName().replace('.', '/') + ";";
  }

  private static native Object invoke0(long id, String descriptor, Object[] args, boolean isVoid);

  private static native void release0(long id);
}
