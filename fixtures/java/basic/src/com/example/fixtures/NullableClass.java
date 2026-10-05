package com.example.fixtures;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

/** Nullability annotations on parameters, returns and fields. */
public class NullableClass {
  @Nullable public String maybe;
  @NonNull public String definitely = "";
  public String unknown;

  public NullableClass() {}

  @NonNull
  public String describe(@Nullable String prefix, @NonNull Object value, String unannotated) {
    return (prefix == null ? "<null>" : prefix) + ":" + value + ":" + unannotated;
  }

  @Nullable
  public static NullableClass find(@NonNull String key) {
    return "missing".equals(key) ? null : new NullableClass();
  }
}
