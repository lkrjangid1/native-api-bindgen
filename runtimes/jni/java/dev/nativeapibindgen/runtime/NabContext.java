// native-api-bindgen React Native runtime. Apache License, Version 2.0.
package dev.nativeapibindgen.runtime;

import android.app.Activity;
import android.app.Application;
import android.content.Context;
import android.os.Bundle;
import java.lang.ref.WeakReference;

/**
 * Gives generated bindings access to the application {@link Context} and the
 * current resumed {@link Activity}. Call {@link #init(Application)} once from
 * {@code Application.onCreate()}. Uses only public SDK APIs.
 */
public final class NabContext {
  private static volatile Application application;
  private static volatile WeakReference<Activity> current = new WeakReference<>(null);

  private NabContext() {}

  /** Registers the application. Idempotent. */
  public static synchronized void init(Application app) {
    if (application != null) return;
    application = app;
    app.registerActivityLifecycleCallbacks(
        new Application.ActivityLifecycleCallbacks() {
          @Override public void onActivityResumed(Activity a) { current = new WeakReference<>(a); }
          @Override public void onActivityPaused(Activity a) {}
          @Override public void onActivityCreated(Activity a, Bundle b) { current = new WeakReference<>(a); }
          @Override public void onActivityStarted(Activity a) {}
          @Override public void onActivityStopped(Activity a) {}
          @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
          @Override public void onActivityDestroyed(Activity a) {
            if (current.get() == a) current = new WeakReference<>(null);
          }
        });
  }

  /** The application context, or null before {@link #init}. */
  public static Context applicationContext() {
    return application;
  }

  /** The most recently created/resumed activity that is still alive, or null. */
  public static Activity currentActivity() {
    return current.get();
  }
}
