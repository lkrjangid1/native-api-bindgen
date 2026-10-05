package com.example.fixtures;

/** An enum with a field and a method. */
public enum EnumClass {
  FIRST(1),
  SECOND(2);

  private final int code;

  EnumClass(int code) { this.code = code; }

  public int code() { return code; }
}
