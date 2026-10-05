import 'dart:ffi' as ffi;

import 'package:objective_c/objective_c.dart' as objc;

import 'src/generated/apple.dart' as ios;

/// A `CGRect` value (passed and returned by value through objc_msgSend).
ios.CGRect rect(double x, double y, double w, double h) {
  final r = ffi.Struct.create<ios.CGRect>();
  r.origin.x = x;
  r.origin.y = y;
  r.size.width = w;
  r.size.height = h;
  return r;
}

/// Device facts read through the generated UIKit/Foundation bindings.
Map<String, String> deviceSummary() {
  final device = ios.UIDevice.currentDevice;
  final info = ios.NSProcessInfo.processInfo;
  final v = info.operatingSystemVersion;
  return {
    'systemName': device.systemName.toDartString(),
    'systemVersion': device.systemVersion.toDartString(),
    'model': device.model.toDartString(),
    'idiom': device.userInterfaceIdiom ==
            ios.UIUserInterfaceIdiom.UIUserInterfaceIdiomPhone
        ? 'phone'
        : '${device.userInterfaceIdiom}',
    'process': info.processName.toDartString(),
    'os': '${v.majorVersion}.${v.minorVersion}.${v.patchVersion}',
  };
}

/// Builds a small native view hierarchy and returns its subview count.
int buildViews() {
  final parent = ios.UIView.alloc().initWithFrame(rect(0, 0, 200, 100));
  for (var i = 0; i < 3; i++) {
    final child = ios.UIView.alloc().initWithFrame(rect(i * 10.0, 0, 10, 10))
      ..tag = i;
    parent.addSubview(child);
  }
  return parent.subviews.count;
}

/// `NSError **` out-parameters surface as [ios.NativeObjCError].
String? listMissingDirectory() {
  try {
    ios.NSFileManager.defaultManager.contentsOfDirectoryAtPath(
      '/nab-does-not-exist'.toNSString(),
    );
    return null;
  } on ios.NativeObjCError catch (e) {
    return '${e.domain} ${e.code}';
  }
}
