# ios_slice

Flutter example using native-api-bindgen generated **iOS** bindings (Foundation + UIKit: `UIDevice`, `UIView`, `UIViewController`, `UIColor`, `NSProcessInfo`, `NSFileManager`) over `package:objective_c`.

Generated code is local-only (derived from your Xcode SDK) and not committed. To run:

```sh
# from the repository root
dart run native_api_bindgen --project examples/flutter/ios_slice generate ios
cd examples/flutter/ios_slice
flutter pub get
xcrun simctl boot "iPhone 17"         # any iOS ≥ 15 simulator
flutter test integration_test -d "iPhone 17"
```

`integration_test/slice_test.dart` covers strings, enum and NS_OPTIONS values, structs by value (`CGRect`, `NSOperatingSystemVersion`), object arguments and nullable returns, class properties, `isA`, `NSError **` → `NativeObjCError`, an availability guard (an iOS 27 API on an older runtime throws `OsVersionError`), explicit release / use-after-release, and 10,000 create/release cycles.

The deployment target is iOS 15.0 (the minimum supported by Xcode 27) and matches `platform.ios.minVersion` in `native_api_bindgen.yaml`.
