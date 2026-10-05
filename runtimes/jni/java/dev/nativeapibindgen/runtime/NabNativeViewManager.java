// native-api-bindgen React Native runtime. Apache License, Version 2.0.
package dev.nativeapibindgen.runtime;

import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import com.facebook.react.uimanager.SimpleViewManager;
import com.facebook.react.uimanager.ThemedReactContext;
import com.facebook.react.uimanager.annotations.ReactProp;

/**
 * {@code <NativeView>}: a container that shows a View created through
 * generated bindings (registered in {@link NabViews}). Served to the New
 * Architecture by React Native's interop layer for view managers.
 */
public final class NabNativeViewManager extends SimpleViewManager<FrameLayout> {
  @Override
  public String getName() {
    return "NabNativeView";
  }

  @Override
  protected FrameLayout createViewInstance(ThemedReactContext context) {
    return new FrameLayout(context);
  }

  @ReactProp(name = "viewId")
  public void setViewId(FrameLayout container, double id) {
    container.removeAllViews();
    View view = NabViews.get((long) id);
    if (view == null) return;
    if (view.getParent() instanceof ViewGroup) {
      ((ViewGroup) view.getParent()).removeView(view);
    }
    container.addView(
        view,
        new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
  }
}
