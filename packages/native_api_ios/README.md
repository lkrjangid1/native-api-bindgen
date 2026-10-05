# native_api_ios

Apple SDK discovery (`xcode-select`, `xcrun`) and Objective-C header extraction through libclang's stable C API (`clang-c/Index.h`), loaded from the locally installed Xcode toolchain. Produces Native IR with per-platform availability, nullability, ObjC selectors, properties, protocols, categories, enums and structs. Never copies SDK files.
