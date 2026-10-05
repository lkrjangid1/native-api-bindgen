package com.example.fixtures;

import androidx.annotation.NonNull;

/** A listener-style interface that Dart code can implement. */
public interface CallbackInterface {
  void onEvent(@NonNull String name, int code);

  boolean shouldContinue();

  default String label() { return "callback"; }

  static CallbackInterface noop() { return null; }
}
