// native-api-bindgen React Native runtime. Apache License, Version 2.0.
#import "NabModuleProvider.h"

#import <ReactCommon/CallInvoker.h>
#import <ReactCommon/TurboModule.h>

#include "NativeApiBindgen.h"

@implementation NabModuleProvider

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
  return std::make_shared<facebook::react::NativeApiBindgen>(params.jsInvoker);
}

@end
