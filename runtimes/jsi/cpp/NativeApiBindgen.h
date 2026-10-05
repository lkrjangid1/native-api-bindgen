// native-api-bindgen React Native runtime. Apache License, Version 2.0.
// Pure C++ Turbo Module (reactnative.dev/docs/the-new-architecture/pure-cxx-modules)
// whose only job is installing `global.__nab`.
#pragma once

#include <NabSpecsJSI.h>

#include <memory>

namespace facebook::react {

class NativeApiBindgen : public NativeApiBindgenCxxSpec<NativeApiBindgen> {
 public:
  explicit NativeApiBindgen(std::shared_ptr<CallInvoker> jsInvoker);
  bool install(jsi::Runtime& rt);
};

} // namespace facebook::react
