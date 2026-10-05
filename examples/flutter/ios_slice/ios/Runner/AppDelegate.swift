import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private let benchView = UIView()

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Hand-written MethodChannel equivalents of generated calls, used only by
    // integration_test/bench_test.dart for comparison.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NabBench") {
      let channel = FlutterMethodChannel(name: "nab/bench", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [benchView] call, result in
        switch call.method {
        case "noop": result(nil)
        case "viewTag": result(benchView.tag)
        case "echoString": result(call.arguments as? String)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
