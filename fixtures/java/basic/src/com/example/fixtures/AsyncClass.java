package com.example.fixtures;

/** Callback-based APIs: same-thread, other-thread, and value-returning. */
public class AsyncClass {
  public AsyncClass() {}

  /** Invokes the callback synchronously on the calling thread. */
  public void load(String key, CallbackInterface callback) {
    callback.onEvent(key, key.length());
  }

  /** Invokes the callback on a new Java thread and waits for it. */
  public void loadOnThread(String key, CallbackInterface callback) throws InterruptedException {
    Thread t = new Thread(() -> callback.onEvent(key, -1));
    t.start();
    t.join();
  }

  /** Returns the callback's answer. */
  public boolean ask(CallbackInterface callback) {
    return callback.shouldContinue();
  }

  /** Returns the callback's label (a default method that Dart implements). */
  public String labelOf(CallbackInterface callback) {
    return callback.label();
  }
}
