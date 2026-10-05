// native-api-bindgen native UI layer. Apache License, Version 2.0.
import Flutter
import UIKit

/// Registers the `dev.nativeapibindgen/view` platform view type.
public class NativeApiUiPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        registrar.register(NabViewFactory(), withId: "dev.nativeapibindgen/view")
    }
}

final class NabViewFactory: NSObject, FlutterPlatformViewFactory {
    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        // The Dart widget keeps the UIView alive while it is shown and passes
        // its address; the platform view borrows it (UIKit retains it once it
        // is in the hierarchy).
        let address = ((args as? [String: Any])?["pointer"] as? NSNumber)?.uintValue ?? 0
        if let raw = UnsafeRawPointer(bitPattern: address) {
            let view = Unmanaged<UIView>.fromOpaque(raw).takeUnretainedValue()
            view.removeFromSuperview()
            return NabPlatformView(view)
        }
        return NabPlatformView(UIView(frame: frame))
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }
}

final class NabPlatformView: NSObject, FlutterPlatformView {
    private let hosted: UIView

    init(_ view: UIView) {
        hosted = view
    }

    func view() -> UIView { hosted }
}
