// native-api-bindgen React Native runtime. Apache License, Version 2.0.
#include "NativeApiBindgen.h"

#if defined(__APPLE__)
#include "NabObjCRuntime.h"

// Provided by the generated bindings (cpp/generated/NabBindingsObjC.cpp).
namespace nab_generated_objc {
const nab::objc::ClassSpec* lookupClass(const std::string& key);
const nab::objc::StructSpec* lookupStruct(const std::string& name);
extern const bool kLongAsBigInt;
} // namespace nab_generated_objc
#else
#include "NabRuntime.h"

// Provided by the generated bindings (cpp/generated/NabBindings.cpp).
namespace nab_generated {
const nab::ClassSpec* lookupClass(const std::string& key);
extern const bool kLongAsBigInt;
} // namespace nab_generated
#endif

namespace facebook::react {

NativeApiBindgen::NativeApiBindgen(std::shared_ptr<CallInvoker> jsInvoker)
    : NativeApiBindgenCxxSpec(std::move(jsInvoker)) {}

bool NativeApiBindgen::install(jsi::Runtime& rt) {
#if defined(__APPLE__)
  nab::objc::install(
      rt,
      jsInvoker_,
      nab::objc::Tables{
          &nab_generated_objc::lookupClass,
          &nab_generated_objc::lookupStruct,
          nab_generated_objc::kLongAsBigInt});
#else
  nab::install(rt, jsInvoker_, &nab_generated::lookupClass, nab_generated::kLongAsBigInt);
#endif
  return true;
}

} // namespace facebook::react
