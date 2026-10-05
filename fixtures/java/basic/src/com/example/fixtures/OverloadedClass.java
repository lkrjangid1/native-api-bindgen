package com.example.fixtures;

/** Overloads that differ by arity and by parameter type, plus varargs. */
public class OverloadedClass {
  private String last = "none";

  public OverloadedClass() {}
  public OverloadedClass(int value) { last = "ctor(int)=" + value; }
  public OverloadedClass(String value) { last = "ctor(String)=" + value; }

  public int add(int a, int b) { return a + b; }
  public long add(long a, long b) { return a + b; }
  public double add(double a, double b) { return a + b; }
  public String add(String a, String b) { return a + b; }

  public void put(String key, int value) { last = "int=" + value; }
  public void put(String key, boolean value) { last = "boolean=" + value; }
  public void put(String key, String value) { last = "String=" + value; }
  public void put(String key, int[] value) { last = "int[]=" + value.length; }
  public void put(String key, byte value) { last = "byte=" + value; }
  public void put(String key, char value) { last = "char=" + value; }
  public void put(String key, short value) { last = "short=" + value; }
  public void put(String key, float value) { last = "float=" + value; }

  /** Which overload ran last. */
  public String last() { return last; }

  public static String join(String separator, String... parts) { return String.join(separator, parts); }
}
