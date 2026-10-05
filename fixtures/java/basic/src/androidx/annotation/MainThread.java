// Minimal test stub written for this project's fixtures. It only mirrors the
// annotation name so the parser's recognition rules can be exercised.
package androidx.annotation;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

@Retention(RetentionPolicy.CLASS)
public @interface MainThread {}
