# Native UI integration layer (TRD §37)

Generated bindings create native views like any other object; this layer
shows them inside the framework's view tree. It is the only part of the
project that uses the Flutter plugin API / React Native view managers.
Everything else stays plugin-free.

## Flutter — `runtimes/flutter/native_api_ui`

```yaml
dependencies:
  native_api_ui: ^0.1.0-beta.1   # pub.dev
```

```dart
// Android: any binding of an android.view.View subclass.
final label = TextView(appContext)..setText$CharSequence('Hi'.toJString());
NativeView.android(view: label);

// iOS: any binding of a UIView subclass.
final view = ios.UILabel.new$()..text = 'Hi'.toNSString();
NativeView.ios(view: view);
```

- Android: `AndroidView` (texture-layer hybrid composition). The `View` is
  registered in `NabViewRegistry` over JNI and picked up by the platform view
  factory `dev.nativeapibindgen/view`; the registry entry is removed when the
  widget is disposed. Consumer ProGuard rules keep the registry.
- iOS: `UiKitView`; the widget keeps the `UIView` alive while it is shown and
  passes its address to the factory, which borrows it.
- Create views on the platform thread (the root isolate on Android and iOS).

## React Native — `NativeView` (exported by the generated library)

```tsx
import { NativeView, TextView, applicationContext } from './native-api-bindings';
const tv = TextView.new(applicationContext());
tv.setText$CharSequence('Hi');
<NativeView view={tv} style={{ width: 200, height: 48 }} />
```

- Runtime builtins `registerView` / `unregisterView` keep the view while the
  component is mounted; the view manager `NabNativeView` (Android
  `NabNativeViewManager`, iOS `NabNativeViewManager`) adds it to its container.
  React Native's interop layer serves these view managers to the New
  Architecture (Fabric).
- Android: add `NabUiPackage()` to the app's packages (see the example's
  `MainApplication.kt`). iOS: compiled from the generated pod.

## Tested (2026-10-05)

| Target | Device | Test |
|---|---|---|
| Flutter Android | API 37 emulator | `TextView` attached to the window, text and non-zero width (`examples/flutter/android_slice`) |
| Flutter iOS | iPhone 17 simulator, iOS 26.4 | `UILabel` in a window, text and non-zero width (`examples/flutter/ios_slice`) |
| React Native Android | API 37 emulator (release) | `TextView` attached, text (`examples/react-native/slice`) |
| React Native iOS | iPhone 17 simulator, iOS 26.4 (release) | `UILabel` in a window, text, width |

Not covered: gestures/accessibility forwarding beyond what platform views
provide, multiple simultaneous hosts of one view, and UI classes that are not
`View`/`UIView` subclasses (not embeddable).
