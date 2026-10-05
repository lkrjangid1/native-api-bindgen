// native-api-bindgen React Native runtime. Apache License, Version 2.0.
// Registers the NativeApiBindgen pure C++ Turbo Module on iOS through the
// app's codegenConfig: "ios": {"modulesProvider": {"NativeApiBindgen": "NabModuleProvider"}}.
#import <Foundation/Foundation.h>
#import <ReactCommon/RCTTurboModule.h>

NS_ASSUME_NONNULL_BEGIN

@interface NabModuleProvider : NSObject <RCTModuleProvider>
@end

NS_ASSUME_NONNULL_END
