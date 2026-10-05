package com.example.fixtures;

/** Static and inner nested types. */
public class NestedClass {
  private String name = "";

  public NestedClass() {}

  public String name() { return name; }

  public static class Builder {
    private String name = "";
    public Builder() {}
    public Builder name(String name) { this.name = name; return this; }
    public NestedClass build() { NestedClass n = new NestedClass(); n.name = name; return n; }
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
