# native_api_react_native_ios

React Native (iOS, New Architecture) target of native-api-bindgen: TypeScript classes generated from Apple IR, backed by a JSI runtime written in Objective-C++ (`runtimes/jsi/objc`). Calls go through `NSInvocation` using the method signature reported by the Objective-C runtime; UIKit members run on the main thread. See `docs/react-native/README.md`.
