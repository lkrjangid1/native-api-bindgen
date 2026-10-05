// native-api-bindgen React Native runtime (JSI <-> JNI).
// Licensed under the Apache License, Version 2.0 (project source).
//
// Generated bindings are *data*: per Java class, a table of members with JNI
// descriptors. This runtime converts JavaScript values to JNI values (and back)
// according to those descriptors, calls JNI, and maps Java exceptions to JS
// errors. Classes are materialised lazily on first access from JS.
#pragma once

#include <jni.h>
#include <jsi/jsi.h>
#include <ReactCommon/CallInvoker.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace nab {

namespace jsi = facebook::jsi;

/// What a generated member does.
enum class MemberKind : uint8_t {
  Constructor,
  StaticMethod,
  InstanceMethod,
  StaticGetter,
  StaticSetter,
  InstanceGetter,
  InstanceSetter,
};

/// One generated member. All strings are static literals.
struct MemberSpec {
  const char* jsName;     // overload-resolved name used from TypeScript
  const char* javaName;   // Java name; "<init>" for constructors
  const char* descriptor; // JNI method or field descriptor
  MemberKind kind;
};

/// One generated class.
struct ClassSpec {
  const char* key;          // binary name with dots: android.os.Handler$Callback
  const char* internalName; // JNI name: android/os/Handler$Callback
  const MemberSpec* members;
  std::size_t memberCount;
};

/// Generated lookup from class key to its table (nullptr if unknown).
using ClassLookup = const ClassSpec* (*)(const std::string& key);

/// Called from JNI_OnLoad on a Java thread: caches the app class loader's
/// runtime classes and registers native methods.
void initialize(JavaVM* vm);

/// Installs `global.__nab` into [rt]. Must be called on the JS thread.
void install(
    jsi::Runtime& rt,
    std::shared_ptr<facebook::react::CallInvoker> invoker,
    ClassLookup lookup,
    bool longAsBigInt);

} // namespace nab
