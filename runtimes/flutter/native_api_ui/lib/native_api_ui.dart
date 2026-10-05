/// Native UI integration layer of native-api-bindgen (TRD §37): hosts a view
/// created through generated bindings in the Flutter widget tree.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:jni/jni.dart';
import 'package:objective_c/objective_c.dart' as objc;

const _viewType = 'dev.nativeapibindgen/view';

/// Shows a native view: an Android `android.view.View` ([NativeView.android])
/// or an iOS `UIView` ([NativeView.ios]) created through generated bindings.
/// The widget keeps the native view alive while it is shown. A view can be
/// shown by one [NativeView] at a time.
class NativeView extends StatefulWidget {
  /// Hosts an Android `View` (any generated binding of a `View` subclass).
  const NativeView.android({super.key, required JObject view})
    : _android = view,
      _ios = null;

  /// Hosts an iOS `UIView` (any generated binding of a `UIView` subclass).
  const NativeView.ios({super.key, required objc.ObjCObject view})
    : _android = null,
      _ios = view;

  final JObject? _android;
  final objc.ObjCObject? _ios;

  @override
  State<NativeView> createState() => _NativeViewState();
}

final class _Registry {
  static final _class = JClass.forName(
    'dev/nativeapibindgen/native_api_ui/NabViewRegistry',
  );
  static final _register = _class.staticMethodId(
    'register',
    '(Landroid/view/View;)J',
  );
  static final _unregister = _class.staticMethodId('unregister', '(J)V');

  static int register(JObject view) =>
      _register.call(_class, jlong.type, [view]);

  static void unregister(int id) => _unregister.call(_class, jvoid.type, [id]);
}

class _NativeViewState extends State<NativeView> {
  int? _androidId;

  @override
  void initState() {
    super.initState();
    final view = widget._android;
    if (view != null) _androidId = _Registry.register(view);
  }

  @override
  void dispose() {
    final id = _androidId;
    if (id != null) _Registry.unregister(id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget._android != null) {
      return AndroidView(
        viewType: _viewType,
        creationParams: {'id': _androidId},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return UiKitView(
      viewType: _viewType,
      creationParams: {'pointer': widget._ios!.ref.pointer.address},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

/// Whether native views can be hosted on this platform.
bool get nativeViewsSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
