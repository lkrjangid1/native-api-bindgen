// Synthetic fixture written for native-api-bindgen (Apache-2.0).
package com.example.fixtures;

import kotlin.coroutines.Continuation;

/**
 * Mirrors how kotlinc compiles {@code suspend fun load(key: String): String}
 * and {@code suspend fun count(): Int}: a trailing Continuation parameter and
 * an Object result. These implementations complete without suspending.
 */
public class SuspendShaped {
  public SuspendShaped() {}

  public Object load(String key, Continuation<? super String> completion) {
    return "loaded:" + key;
  }

  public Object count(Continuation<? super Integer> completion) {
    return 3;
  }
}
