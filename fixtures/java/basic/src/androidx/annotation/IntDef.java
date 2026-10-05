// Minimal test stub written for this project's fixtures.
package androidx.annotation;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

@Retention(RetentionPolicy.SOURCE)
public @interface IntDef {
  int[] value() default {};
  boolean flag() default false;
}
