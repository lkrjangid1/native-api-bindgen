package com.example.fixtures;

/** Static and inner nested types. */
public class NestedClass {
  public NestedClass() {}

  public static class Builder {
    public Builder() {}
    public Builder name(String name) { return this; }
    public NestedClass build() { return new NestedClass(); }
  }

  public class Inner {
    public Inner() {}
    public int value() { return 0; }
  }

  public interface Listener {
    void onChange(NestedClass source);
  }

  private static class Hidden {}
}
