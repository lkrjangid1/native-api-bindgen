// Minimal compile-time stub written for this project's fixtures. It only
// mirrors the name and shape of kotlin.coroutines.Continuation so a Java
// fixture can declare a method shaped like a compiled Kotlin suspend
// function. It is never packaged with the fixture classes; at run time the
// real class comes from kotlin-stdlib.
package kotlin.coroutines;

public interface Continuation<T> {
  void resumeWith(Object result);
}
