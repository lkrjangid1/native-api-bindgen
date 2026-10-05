package com.example.fixtures;

/** Overloads that differ by arity and by parameter type, plus varargs. */
public class OverloadedClass {
  public OverloadedClass() {}
  public OverloadedClass(int value) {}
  public OverloadedClass(String value) {}

  public int add(int a, int b) { return a + b; }
  public long add(long a, long b) { return a + b; }
  public double add(double a, double b) { return a + b; }
  public String add(String a, String b) { return a + b; }

  public void put(String key, int value) {}
  public void put(String key, boolean value) {}
  public void put(String key, String value) {}
  public void put(String key, int[] value) {}
  public void put(String key, byte value) {}
  public void put(String key, char value) {}
  public void put(String key, short value) {}
  public void put(String key, float value) {}

  public static String join(String separator, String... parts) { return ""; }
}
