// native-api-bindgen React Native runtime (JSI <-> Objective-C).
// Licensed under the Apache License, Version 2.0 (project source).
//
// Generated bindings are *data*: per Objective-C class or protocol, a table of
// members (selector + a JS conversion code per value). The native ABI of each
// call comes from the Objective-C runtime (NSMethodSignature), so this runtime
// never guesses argument layouts; it converts JS values, invokes through
// NSInvocation, and maps NSException / NSError to JS errors.
#pragma once

#include <jsi/jsi.h>
#include <ReactCommon/CallInvoker.h>

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace nab::objc {

namespace jsi = facebook::jsi;

/// What a generated member does.
enum class MemberKind : uint8_t {
  ClassMethod,
  InstanceMethod,
  ClassGetter,
  ClassSetter,
  InstanceGetter,
  InstanceSetter,
};

/// Member flags.
enum MemberFlags : uint8_t {
  /// Returns a +1 reference (alloc/new/copy/mutableCopy families).
  kOwned = 1,
  /// `init` family: consumes the receiver and returns a +1 reference.
  kInit = 2,
  /// Must run on the main thread (UIKit).
  kMainThread = 4,
  /// The last selector argument is a hidden `NSError **`.
  kErrorOut = 8,
};

/// One generated member. All strings are static literals.
///
/// [conv] has one code per JS-visible value, the return value first:
/// `v` void, `z` boolean, `n` number, `j` 64-bit integer (bigint or number
/// depending on the TypeScript mode), `s` NSString <-> string, `o` object
/// handle, `S<Name>;` struct <-> plain object (the name resolves anonymous
/// structs, encoded as `{?=...}`), `B<key>;` JS function -> Objective-C block
/// (generated factory [key], see NabObjCBlocks.h). Setters use `v` + the
/// value code.
struct MemberSpec {
  const char* jsName;   // stable key used from TypeScript (`-sel`, `P-name=`)
  const char* selector; // Objective-C selector
  const char* conv;
  MemberKind kind;
  uint8_t flags;
};

/// One generated class or protocol.
struct ClassSpec {
  const char* key;      // IR id: UIKit.UIView
  const char* objcName; // Objective-C name: UIView
  bool isProtocol;
  const MemberSpec* members;
  std::size_t memberCount;
};

/// Field names of a struct, in declaration order (types come from the
/// runtime type encoding).
struct StructSpec {
  const char* name; // C name: CGRect
  const char* const* fields;
  const char* const* fieldStructs; // struct name of struct-typed fields, else nullptr
  std::size_t fieldCount;
};

struct BlockFactory; // NabObjCBlocks.h (Objective-C++)

/// Generated tables.
struct Tables {
  const ClassSpec* (*lookupClass)(const std::string& key);
  const StructSpec* (*lookupStruct)(const std::string& name);
  bool longAsBigInt;
  const BlockFactory* (*lookupBlock)(const std::string& key);
};

/// Installs `global.__nab` into [rt]. Must be called on the JS thread.
void install(
    jsi::Runtime& rt,
    std::shared_ptr<facebook::react::CallInvoker> invoker,
    const Tables& tables);

} // namespace nab::objc
