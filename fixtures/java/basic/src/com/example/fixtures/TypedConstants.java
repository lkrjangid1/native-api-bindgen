package com.example.fixtures;

/**
 * Constants typed by external {@code @IntDef}, {@code @LongDef} and
 * {@code @StringDef} annotations (see {@code fixtures/java/basic/annotations}),
 * the way the Android SDK ships them in {@code annotations.zip}.
 */
public class TypedConstants {
    public static final int MODE_OFF = 0;
    public static final int MODE_ON = 1;
    public static final int MODE_AUTO = 2;

    public static final int STYLE_BOLD = 1;
    public static final int STYLE_ITALIC = 2;
    public static final int STYLE_UNDERLINE = 4;

    public static final long SIZE_SMALL = 1L;
    public static final long SIZE_LARGE = 1L << 40;

    public static final String COLOR_RED = "red";
    public static final String COLOR_BLUE = "blue";

    private int mode = MODE_OFF;
    private int style;
    private long size = SIZE_SMALL;
    private String color = COLOR_RED;

    public TypedConstants() {}

    public int getMode() { return mode; }

    public void setMode(int mode) { this.mode = mode; }

    public int getStyle() { return style; }

    public void setStyle(int style) { this.style = style; }

    public long getSize() { return size; }

    public void setSize(long size) { this.size = size; }

    public String getColor() { return color; }

    public void setColor(String color) { this.color = color; }

    public static boolean isBold(int style) { return (style & STYLE_BOLD) != 0; }
}
