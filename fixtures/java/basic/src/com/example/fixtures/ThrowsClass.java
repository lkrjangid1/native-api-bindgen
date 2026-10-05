package com.example.fixtures;

import java.io.IOException;

/** Checked and unchecked exceptions. */
public class ThrowsClass {
  public ThrowsClass() {}

  public void read() throws IOException { throw new IOException("disk on fire"); }

  public static int parse(String text) throws NumberFormatException, IllegalStateException {
    return Integer.parseInt(text);
  }
}
