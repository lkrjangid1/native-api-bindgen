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
}
