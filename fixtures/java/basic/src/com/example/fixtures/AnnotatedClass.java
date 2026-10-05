package com.example.fixtures;

import androidx.annotation.IntDef;
import androidx.annotation.MainThread;
import androidx.annotation.RequiresPermission;
import androidx.annotation.WorkerThread;

/** Constants plus semantic and preservable annotations. */
public class AnnotatedClass {
  public static final int MODE_A = 1;
  public static final int MODE_B = 2;
  public static final long BIG = 9223372036854775807L;
  public static final float HALF = 0.5f;
  public static final double TINY = 1.0E-300;
  public static final char LETTER = 'x';
  public static final boolean ENABLED = true;
  public static final String ACTION = "com.example.ACTION \"quoted\" $dollar \\slash";
  public static final String UNICODE = "café ☃";
  public static int counter;

  public AnnotatedClass() {}

  @MainThread
  public void render() {}

  @WorkerThread
  @RequiresPermission(anyOf = {"android.permission.CAMERA", "android.permission.RECORD_AUDIO"})
  public void capture(@IntDef({MODE_A, MODE_B}) int mode) {}

  @Deprecated
  public void old() {}
}
