package com.example.fixtures;

import java.util.List;
import java.util.Map;

/** Generic type parameters, bounds and wildcards. */
public class GenericClass<T extends CharSequence> {
  public GenericClass(T value) {}

  public T get() { return null; }

  public void set(T value) {}

  public static <K, V extends Comparable<V>> Map<K, V> index(List<? extends K> keys, List<? super V> values) {
    return null;
  }

  public <E> E first(List<E> items) { return null; }
}
