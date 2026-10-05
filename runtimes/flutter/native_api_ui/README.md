# native_api_ui

The native UI integration layer of native-api-bindgen (TRD §37): hosts a view
created through generated bindings in the Flutter widget tree. This is the only
part of the project that uses the Flutter plugin API (platform views need it).

```dart
final label = TextView(applicationContext)..setText('Hi'.toJString());
NativeView.android(view: label);          // Android: android.view.View

final view = ios.UILabel.new$()..text = 'Hi'.toNSString();
NativeView.ios(view: view);               // iOS: UIView
```

- Android uses `AndroidView` (texture layer hybrid composition); the `View` is
  handed to the platform view factory through a JNI-called registry
  (`NabViewRegistry`). Create it on the platform thread (the root isolate).
- iOS uses `UiKitView`; the widget keeps the `UIView` alive while it is shown.
- Views must not already have a parent. Other UI classes are not embeddable.
