// native-api-bindgen React Native runtime. Apache License, Version 2.0.
package dev.nativeapibindgen.runtime;

import com.facebook.react.ReactPackage;
import com.facebook.react.bridge.NativeModule;
import com.facebook.react.bridge.ReactApplicationContext;
import java.util.Collections;
import java.util.List;

/** Registers {@link NabNativeViewManager}: add to the app's packages. */
public final class NabUiPackage implements ReactPackage {
  @Override
  public List<NativeModule> createNativeModules(ReactApplicationContext context) {
    return Collections.emptyList();
  }

  // Raw type: the generic signature of ReactPackage differs across React
  // Native versions (Kotlin `ViewManager<in Nothing, in Nothing>`).
  @Override
  @SuppressWarnings({"rawtypes", "unchecked"})
  public List createViewManagers(ReactApplicationContext context) {
    return Collections.singletonList(new NabNativeViewManager());
  }
}
