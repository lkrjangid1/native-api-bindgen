// native-api-bindgen React Native runtime. Apache License, Version 2.0.
package dev.nativeapibindgen.runtime;

import android.view.View;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Views created through generated bindings that a {@code <NativeView>} shows
 * (see {@link NabNativeViewManager}). Called from native code.
 */
public final class NabViews {
  private static final ConcurrentHashMap<Long, View> views = new ConcurrentHashMap<>();
  private static final AtomicLong next = new AtomicLong(1);

  private NabViews() {}

  /** Registers [view] and returns its id. */
  public static long register(Object view) {
    long id = next.getAndIncrement();
    views.put(id, (View) view);
    return id;
  }

  /** Forgets [id]. */
  public static void unregister(long id) {
    views.remove(id);
  }

  /** The view registered as [id], or null. */
  public static View get(long id) {
    return views.get(id);
  }
}
