// native-api-bindgen React Native runtime. Apache License, Version 2.0.
#include "NativeApiBindgen.h"

#include "NabRuntime.h"

// Provided by the generated bindings (cpp/generated/NabBindings.cpp).
namespace nab_generated {
const nab::ClassSpec* lookupClass(const std::string& key);
extern const bool kLongAsBigInt;
} // namespace nab_generated

namespace facebook::react {

NativeApiBindgen::NativeApiBindgen(std::shared_ptr<CallInvoker> jsInvoker)
    : NativeApiBindgenCxxSpec(std::move(jsInvoker)) {}

bool NativeApiBindgen::install(jsi::Runtime& rt) {
  nab::install(rt, jsInvoker_, &nab_generated::lookupClass, nab_generated::kLongAsBigInt);
  return true;
}

} // namespace facebook::react
