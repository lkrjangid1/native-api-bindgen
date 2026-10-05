package com.example.fixtures;

/** Abstract class inheriting size() from two interfaces without redeclaring it. */
public abstract class DualImpl implements Sizable, Countable, Marker {
  public static DualImpl create(int n) {
    return new DualImpl() {
      @Override public int size() { return n; }
    };
  }
}
