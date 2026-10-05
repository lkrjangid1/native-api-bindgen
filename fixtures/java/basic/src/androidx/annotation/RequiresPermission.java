// Minimal test stub written for this project's fixtures.
package androidx.annotation;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

@Retention(RetentionPolicy.CLASS)
public @interface RequiresPermission {
  String value() default "";
  String[] anyOf() default {};
}
