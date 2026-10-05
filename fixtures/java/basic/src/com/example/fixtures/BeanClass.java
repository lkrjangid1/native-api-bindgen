// Synthetic fixture written for native-api-bindgen (Apache-2.0).
package com.example.fixtures;

/** Java bean accessors (TRD §60). */
public class BeanClass {
  private String title = "untitled";
  private boolean enabled;
  private int count;

  public BeanClass() {}

  /** Read-write: getTitle/setTitle. */
  public String getTitle() { return title; }
  public void setTitle(String title) { this.title = title; }

  /** Boolean read-write: isEnabled/setEnabled. */
  public boolean isEnabled() { return enabled; }
  public void setEnabled(boolean enabled) { this.enabled = enabled; }

  /** Read-only. */
  public int getCount() { return count; }

  /** Acronym stays upper case: property URL. */
  public String getURL() { return "https://example.com/" + count; }

  /** Not a property: has a parameter. */
  public String getLabel(int index) { return title + "#" + index; }

  /** Not a property setter: mismatched type. */
  public void setCount(String count) { this.count = Integer.parseInt(count); }

  public void increment() { count++; }
}
