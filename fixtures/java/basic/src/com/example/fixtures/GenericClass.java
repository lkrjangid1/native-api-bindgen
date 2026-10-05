package com.example.fixtures;

import java.util.List;
import java.util.Map;

/** Generic type parameters, bounds and wildcards. */
public class GenericClass<T extends CharSequence> {
  private T value;

  public GenericClass(T value) { this.value = value; }

  public T get() { return value; }

  public void set(T value) { this.value = value; }

  public static <K, V extends Comparable<V>> Map<K, V> index(List<? extends K> keys, List<? super V> values) {
    return null;
  }

  public <E> E first(List<E> items) { return items.isEmpty() ? null : items.get(0); }

  /** A parameterized result: {@code GenericClass<String>}. */
  public static GenericClass<String> of(String value) { return new GenericClass<>(value); }

  /** java.util collections in signatures. */
  public static List<String> names(String a, String b) { return new java.util.ArrayList<>(List.of(a, b)); }

  public static Map<String, Integer> lengths(List<String> items) {
    Map<String, Integer> out = new java.util.HashMap<>();
    for (String s : items) out.put(s, s.length());
    return out;
  }
}
