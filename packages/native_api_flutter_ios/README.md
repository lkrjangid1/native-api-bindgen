# native_api_flutter_ios

Emits Dart bindings over `package:objective_c` from Apple IR: extension types per Objective-C class/protocol, typed `objc_msgSend` trampolines, ARC ownership by method family, properties, structs (`ffi.Struct`), enums, and iOS availability guards. Core Foundation/ObjC types already provided by `package:objective_c` are referenced, not regenerated.
