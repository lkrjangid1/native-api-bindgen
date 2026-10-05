package com.example.fixtures;

/** Inherits from a class and two interfaces that share a method name. */
public class MultiParent extends NestedClass implements Comparable<MultiParent>, CallbackInterface, Cloneable {
  public MultiParent() {}

  @Override public int compareTo(MultiParent other) { return 0; }

  @Override public void onEvent(String name, int code) {}

  @Override public boolean shouldContinue() { return true; }
}
