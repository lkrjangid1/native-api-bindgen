// native-api-bindgen React Native runtime (JSI <-> Objective-C).
// Licensed under the Apache License, Version 2.0 (project source).
// Compiled with ARC (-fobjc-arc).
#import "NabObjCRuntime.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <cstring>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#if !__has_feature(objc_arc)
#error "NabObjCRuntime.mm must be compiled with ARC"
#endif

namespace nab::objc {
namespace {

using facebook::react::CallInvoker;

Tables gTables{};
std::shared_ptr<CallInvoker> gInvoker;

// ------------------------------------------------------------------ errors

jsi::Value makeError(jsi::Runtime& rt, const char* name, const std::string& message) {
  auto ctor = rt.global().getPropertyAsFunction(rt, "Error");
  auto err = ctor.callAsConstructor(rt, jsi::String::createFromUtf8(rt, message)).asObject(rt);
  err.setProperty(rt, "name", name);
  return jsi::Value(rt, err);
}

[[noreturn]] void fail(jsi::Runtime& rt, const char* name, const std::string& message) {
  throw jsi::JSError(rt, makeError(rt, name, message));
}

[[noreturn]] void typeError(jsi::Runtime& rt, const std::string& message) {
  fail(rt, "TypeError", "native-api-bindgen: " + message);
}

std::string utf8(NSString* s) {
  if (s == nil) return "";
  const char* c = s.UTF8String;
  return c == nullptr ? "" : std::string(c);
}

// ------------------------------------------------------------------ strings

jsi::Value toJsString(jsi::Runtime& rt, NSString* s) {
  if (s == nil) return jsi::Value::null();
  const NSUInteger n = s.length;
  std::u16string u(static_cast<std::size_t>(n), u'\0');
  if (n > 0) [s getCharacters:reinterpret_cast<unichar*>(u.data()) range:NSMakeRange(0, n)];
  return jsi::String::createFromUtf16(rt, u);
}

NSString* toNSString(jsi::Runtime& rt, const jsi::Value& v) {
  if (v.isNull() || v.isUndefined()) return nil;
  if (!v.isString()) typeError(rt, "expected string");
  const std::u16string u = v.getString(rt).utf16(rt);
  return [NSString stringWithCharacters:reinterpret_cast<const unichar*>(u.data()) length:u.size()];
}

// ------------------------------------------------------------------ handles

/// A JS-owned strong reference to an Objective-C object. Released when the
/// JS object is garbage-collected or explicitly via `__nab.release(h)`. The
/// final release happens on the main thread because UIKit objects must be
/// deallocated there.
class Handle : public jsi::HostObject {
 public:
  explicit Handle(id object) : object_(object) {}
  ~Handle() override { release(); }

  id object(jsi::Runtime& rt) const {
    if (object_ == nil) fail(rt, "UseAfterReleaseError", "the native object was released");
    return object_;
  }
  bool released() const { return object_ == nil; }
  void release() {
    id o = object_;
    object_ = nil;
    if (o != nil && ![NSThread isMainThread]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        (void)o;
      });
    }
  }

 private:
  __strong id object_;
};

jsi::Value wrap(jsi::Runtime& rt, id object) {
  if (object == nil) return jsi::Value::null();
  return jsi::Object::createFromHostObject(rt, std::make_shared<Handle>(object));
}

std::shared_ptr<Handle> handleOf(jsi::Runtime& rt, const jsi::Value& v) {
  if (!v.isObject()) return nullptr;
  auto o = v.getObject(rt);
  if (!o.isHostObject<Handle>(rt)) return nullptr;
  return o.getHostObject<Handle>(rt);
}

id objectArg(jsi::Runtime& rt, const jsi::Value& v, const char* what) {
  if (v.isNull() || v.isUndefined()) return nil;
  auto h = handleOf(rt, v);
  if (!h) typeError(rt, std::string("expected a native object for ") + what);
  return h->object(rt);
}

// ------------------------------------------------------------------ encodings

const char* skipQualifiers(const char* t) {
  while (*t != '\0' && std::strchr("rnNoORV", *t) != nullptr) t++;
  return t;
}

std::string structName(const char* enc) {
  const char* p = enc + 1;
  const char* end = p;
  while (*end != '\0' && *end != '=' && *end != '}') end++;
  return std::string(p, static_cast<std::size_t>(end - p));
}

struct Field {
  std::string enc;
  std::size_t offset;
};

std::vector<Field> structFields(const char* enc) {
  std::vector<Field> out;
  const char* p = std::strchr(enc, '=');
  if (p == nullptr) return out;
  p++;
  std::size_t offset = 0;
  while (*p != '\0' && *p != '}') {
    NSUInteger size = 0;
    NSUInteger align = 1;
    const char* next = NSGetSizeAndAlignment(p, &size, &align);
    if (align > 0) offset = (offset + align - 1) / align * align;
    out.push_back({std::string(p, static_cast<std::size_t>(next - p)), offset});
    offset += size;
    p = next;
  }
  return out;
}

/// Struct table for an encoding name; [hint] (the declared C name) resolves
/// anonymous structs (`{?=...}`) and tag/typedef mismatches.
const StructSpec* structSpec(jsi::Runtime& rt, const std::string& name, const char* hint) {
  const StructSpec* s = name == "?" ? nullptr : gTables.lookupStruct(name);
  if (s == nullptr && !name.empty() && name[0] == '_') s = gTables.lookupStruct(name.substr(1));
  if (s == nullptr && hint != nullptr) s = gTables.lookupStruct(hint);
  if (s == nullptr) typeError(rt, "struct " + (hint != nullptr ? std::string(hint) : name) + " is not part of the generated bindings");
  return s;
}

// ------------------------------------------------------------------ scalars

int64_t toInt64(jsi::Runtime& rt, const jsi::Value& v) {
  if (v.isBigInt()) return v.getBigInt(rt).asInt64(rt);
  if (v.isNumber()) return static_cast<int64_t>(v.getNumber());
  if (v.isBool()) return v.getBool() ? 1 : 0;
  typeError(rt, "expected number or bigint");
}

uint64_t toUint64(jsi::Runtime& rt, const jsi::Value& v) {
  if (v.isBigInt()) return v.getBigInt(rt).asUint64(rt);
  return static_cast<uint64_t>(toInt64(rt, v));
}

double toDouble(jsi::Runtime& rt, const jsi::Value& v) {
  if (v.isNumber()) return v.getNumber();
  if (v.isBigInt()) return static_cast<double>(v.getBigInt(rt).asInt64(rt));
  typeError(rt, "expected number");
}

bool isScalar(char c) {
  return std::strchr("cCsSiIlLqQfdB", c) != nullptr;
}

void writeValue(jsi::Runtime& rt, const char* enc, const jsi::Value& v, void* dst, const char* hint = nullptr);

void writeScalar(jsi::Runtime& rt, char c, const jsi::Value& v, void* dst) {
  switch (c) {
    case 'B': *static_cast<bool*>(dst) = v.isBool() ? v.getBool() : toInt64(rt, v) != 0; break;
    case 'c': *static_cast<int8_t*>(dst) = static_cast<int8_t>(v.isBool() ? (v.getBool() ? 1 : 0) : toInt64(rt, v)); break;
    case 'C': *static_cast<uint8_t*>(dst) = static_cast<uint8_t>(toInt64(rt, v)); break;
    case 's': *static_cast<int16_t*>(dst) = static_cast<int16_t>(toInt64(rt, v)); break;
    case 'S': *static_cast<uint16_t*>(dst) = static_cast<uint16_t>(toInt64(rt, v)); break;
    case 'i': *static_cast<int32_t*>(dst) = static_cast<int32_t>(toInt64(rt, v)); break;
    case 'I': *static_cast<uint32_t*>(dst) = static_cast<uint32_t>(toInt64(rt, v)); break;
    case 'l':
    case 'q': *static_cast<int64_t*>(dst) = toInt64(rt, v); break;
    case 'L':
    case 'Q': *static_cast<uint64_t*>(dst) = toUint64(rt, v); break;
    case 'f': *static_cast<float*>(dst) = static_cast<float>(toDouble(rt, v)); break;
    case 'd': *static_cast<double*>(dst) = toDouble(rt, v); break;
    default: typeError(rt, std::string("unsupported scalar encoding ") + c);
  }
}

jsi::Value readScalar(jsi::Runtime& rt, char c, const void* src) {
  const bool big = gTables.longAsBigInt;
  switch (c) {
    case 'B': return jsi::Value(*static_cast<const bool*>(src));
    case 'c': return jsi::Value(static_cast<double>(*static_cast<const int8_t*>(src)));
    case 'C': return jsi::Value(static_cast<double>(*static_cast<const uint8_t*>(src)));
    case 's': return jsi::Value(static_cast<double>(*static_cast<const int16_t*>(src)));
    case 'S': return jsi::Value(static_cast<double>(*static_cast<const uint16_t*>(src)));
    case 'i': return jsi::Value(static_cast<double>(*static_cast<const int32_t*>(src)));
    case 'I': return jsi::Value(static_cast<double>(*static_cast<const uint32_t*>(src)));
    case 'l':
    case 'q': {
      const int64_t x = *static_cast<const int64_t*>(src);
      if (big) return jsi::BigInt::fromInt64(rt, x);
      return jsi::Value(static_cast<double>(x));
    }
    case 'L':
    case 'Q': {
      const uint64_t x = *static_cast<const uint64_t*>(src);
      if (big) return jsi::BigInt::fromUint64(rt, x);
      return jsi::Value(static_cast<double>(x));
    }
    case 'f': return jsi::Value(static_cast<double>(*static_cast<const float*>(src)));
    case 'd': return jsi::Value(*static_cast<const double*>(src));
    default: typeError(rt, std::string("unsupported scalar encoding ") + c);
  }
}

// ------------------------------------------------------------------ structs

void writeStruct(jsi::Runtime& rt, const char* enc, const jsi::Value& v, void* dst, const char* hint) {
  if (!v.isObject()) typeError(rt, "expected an object for struct " + structName(enc));
  auto obj = v.getObject(rt);
  const StructSpec* spec = structSpec(rt, structName(enc), hint);
  const auto fields = structFields(enc);
  if (fields.size() != spec->fieldCount) typeError(rt, "layout mismatch for struct " + structName(enc));
  for (std::size_t i = 0; i < fields.size(); i++) {
    auto fv = obj.getProperty(rt, spec->fields[i]);
    if (fv.isUndefined()) typeError(rt, std::string("missing field ") + spec->fields[i] + " of " + spec->name);
    writeValue(rt, fields[i].enc.c_str(), fv, static_cast<uint8_t*>(dst) + fields[i].offset, spec->fieldStructs[i]);
  }
}

jsi::Value readValue(jsi::Runtime& rt, const char* enc, const void* src, const char* hint = nullptr);

jsi::Value readStruct(jsi::Runtime& rt, const char* enc, const void* src, const char* hint) {
  const StructSpec* spec = structSpec(rt, structName(enc), hint);
  const auto fields = structFields(enc);
  if (fields.size() != spec->fieldCount) typeError(rt, "layout mismatch for struct " + structName(enc));
  jsi::Object out(rt);
  for (std::size_t i = 0; i < fields.size(); i++) {
    out.setProperty(
        rt,
        spec->fields[i],
        readValue(rt, fields[i].enc.c_str(), static_cast<const uint8_t*>(src) + fields[i].offset, spec->fieldStructs[i]));
  }
  return jsi::Value(rt, out);
}

void writeValue(jsi::Runtime& rt, const char* enc, const jsi::Value& v, void* dst, const char* hint) {
  enc = skipQualifiers(enc);
  if (*enc == '{') return writeStruct(rt, enc, v, dst, hint);
  if (isScalar(*enc)) return writeScalar(rt, *enc, v, dst);
  typeError(rt, std::string("unsupported field encoding ") + enc);
}

jsi::Value readValue(jsi::Runtime& rt, const char* enc, const void* src, const char* hint) {
  enc = skipQualifiers(enc);
  if (*enc == '{') return readStruct(rt, enc, src, hint);
  if (isScalar(*enc)) return readScalar(rt, *enc, src);
  typeError(rt, std::string("unsupported field encoding ") + enc);
}

// ------------------------------------------------------------------ calls

/// One JS-visible value of a member's conversion string.
struct Code {
  char kind;
  std::string structName; // for 'S'
};

std::vector<Code> parseConv(const char* conv) {
  std::vector<Code> out;
  for (const char* p = conv; *p != '\0'; p++) {
    Code c{*p, {}};
    if (*p == 'S') {
      const char* end = std::strchr(p + 1, ';');
      if (end == nullptr) end = p + 1 + std::strlen(p + 1);
      c.structName.assign(p + 1, static_cast<std::size_t>(end - p - 1));
      p = *end == '\0' ? end - 1 : end;
    }
    out.push_back(std::move(c));
  }
  return out;
}

/// State of one call, shared between the JS thread and the thread that
/// invokes (main thread for UIKit, a background queue for Promise variants).
struct Call {
  NSInvocation* invocation = nil;
  const MemberSpec* member = nullptr;
  char retCode = 'v';
  std::string retStruct;
  std::string retEnc;
  // Outcome.
  bool exception = false;
  std::string exceptionName, exceptionReason;
  __strong id retObject = nil;
  std::vector<uint8_t> retBytes;
  void* errorStorage = nullptr; // written by the callee (autoreleased NSError*)
  void* errorPointer = nullptr; // &errorStorage, passed as NSError**
  __strong NSError* error = nil;
};

void invokeNow(Call& c) {
  @autoreleasepool {
    @try {
      [c.invocation invoke];
    } @catch (NSException* e) {
      c.exception = true;
      c.exceptionName = utf8(e.name);
      c.exceptionReason = utf8(e.reason);
      return;
    }
    const char r = *skipQualifiers(c.retEnc.c_str());
    if (r == '@') {
      void* raw = nullptr;
      [c.invocation getReturnValue:&raw];
      if (c.member->flags & (kOwned | kInit)) {
        c.retObject = (__bridge_transfer id)raw;
      } else {
        c.retObject = (__bridge id)raw;
      }
    } else if (r != 'v') {
      c.retBytes.resize(c.invocation.methodSignature.methodReturnLength);
      [c.invocation getReturnValue:c.retBytes.data()];
    }
    if (c.member->flags & kErrorOut) {
      c.error = (__bridge NSError*)c.errorStorage; // retained before the pool drains
    }
  }
}

/// Converts the outcome to JS (JS thread). Throws on failure.
jsi::Value outcome(jsi::Runtime& rt, Call& c) {
  if (c.exception) {
    auto err = makeError(rt, "NativeObjCException", c.exceptionName + ": " + c.exceptionReason).asObject(rt);
    err.setProperty(rt, "exceptionName", jsi::String::createFromUtf8(rt, c.exceptionName));
    err.setProperty(rt, "reason", jsi::String::createFromUtf8(rt, c.exceptionReason));
    throw jsi::JSError(rt, jsi::Value(rt, err));
  }
  if (c.member->flags & kErrorOut) {
    bool failed = c.error != nil;
    if (c.retCode == 'z' && !c.retBytes.empty()) failed = failed && c.retBytes[0] == 0;
    if (c.retCode == 'o' || c.retCode == 's') failed = failed && c.retObject == nil;
    if (failed) {
      NSError* e = c.error;
      auto err = makeError(rt, "NativeObjCError", utf8(e.localizedDescription)).asObject(rt);
      err.setProperty(rt, "domain", jsi::String::createFromUtf8(rt, utf8(e.domain)));
      err.setProperty(rt, "code", jsi::Value(static_cast<double>(e.code)));
      throw jsi::JSError(rt, jsi::Value(rt, err));
    }
  }
  switch (c.retCode) {
    case 'v': return jsi::Value::undefined();
    case 'o': return wrap(rt, c.retObject);
    case 's': {
      if (c.retObject == nil) return jsi::Value::null();
      if (![c.retObject isKindOfClass:[NSString class]]) return wrap(rt, c.retObject);
      return toJsString(rt, (NSString*)c.retObject);
    }
    default:
      return readValue(rt, c.retEnc.c_str(), c.retBytes.data(), c.retStruct.empty() ? nullptr : c.retStruct.c_str());
  }
}

bool isStatic(MemberKind k) {
  return k == MemberKind::ClassMethod || k == MemberKind::ClassGetter || k == MemberKind::ClassSetter;
}

/// Host-function body shared by every generated member.
/// JS calling convention: (async: boolean, [self], ...args).
jsi::Value callMember(jsi::Runtime& rt, const ClassSpec* cls, const MemberSpec* m, const jsi::Value* args, std::size_t count) {
  const bool async = count > 0 && args[0].isBool() && args[0].getBool();
  std::size_t i = 1;
  id target = nil;
  if (isStatic(m->kind)) {
    if (cls->isProtocol) typeError(rt, std::string("class member on protocol ") + cls->objcName);
    target = objc_getClass(cls->objcName);
    if (target == nil) {
      fail(rt, "NativeApiUnavailableError", std::string("E010 RUNTIME_BINDING_FAILURE: class ") + cls->objcName + " is not available on this OS version");
    }
  } else {
    if (count <= i) typeError(rt, "missing receiver");
    auto h = handleOf(rt, args[i]);
    if (!h) typeError(rt, std::string("receiver is not a native object for ") + m->jsName);
    target = h->object(rt);
    i++;
  }
  SEL sel = sel_registerName(m->selector);
  NSMethodSignature* sig = [target methodSignatureForSelector:sel];
  if (sig == nil) {
    fail(rt, "NativeApiUnavailableError", std::string("E010 RUNTIME_BINDING_FAILURE: ") + cls->objcName + " does not respond to " + m->selector);
  }
  auto call = std::make_shared<Call>();
  const std::vector<Code> codes = parseConv(m->conv);
  if (codes.empty()) typeError(rt, std::string("bad conversion codes for ") + m->selector);
  call->member = m;
  call->retCode = codes[0].kind;
  call->retStruct = codes[0].structName;
  call->retEnc = sig.methodReturnType;
  NSInvocation* inv = [NSInvocation invocationWithMethodSignature:sig];
  inv.target = target;
  inv.selector = sel;
  const std::size_t jsParams = codes.size() - 1;
  const std::size_t nativeParams = sig.numberOfArguments - 2;
  const bool errorOut = (m->flags & kErrorOut) != 0;
  if (nativeParams != jsParams + (errorOut ? 1 : 0)) {
    typeError(rt, std::string("signature mismatch for ") + m->selector);
  }
  if (count - i < jsParams) typeError(rt, std::string("not enough arguments for ") + m->jsName);
  // Object arguments stay strongly referenced here until retainArguments:
  // NSInvocation stores raw pointers, and an NSString converted from a JS
  // string has no other owner.
  std::vector<id> keep;
  keep.reserve(jsParams);
  for (std::size_t p = 0; p < jsParams; p++) {
    const jsi::Value& v = args[i + p];
    const char* enc = skipQualifiers([sig getArgumentTypeAtIndex:p + 2]);
    const NSUInteger index = p + 2;
    const Code& code = codes[p + 1];
    switch (code.kind) {
      case 'o': {
        id o = objectArg(rt, v, m->selector);
        keep.push_back(o);
        [inv setArgument:&o atIndex:index];
        break;
      }
      case 's': {
        id s = v.isString() ? toNSString(rt, v) : objectArg(rt, v, m->selector);
        keep.push_back(s);
        [inv setArgument:&s atIndex:index];
        break;
      }
      default: {
        NSUInteger size = 0;
        NSGetSizeAndAlignment(enc, &size, nullptr);
        std::vector<uint8_t> buf(size, 0);
        writeValue(rt, enc, v, buf.data(), code.structName.empty() ? nullptr : code.structName.c_str());
        [inv setArgument:buf.data() atIndex:index];
      }
    }
  }
  if (errorOut) {
    call->errorPointer = &call->errorStorage;
    [inv setArgument:&call->errorPointer atIndex:jsParams + 2];
  }
  [inv retainArguments];
  if (m->flags & kInit) {
    // `init` consumes its receiver; the handle keeps its own reference.
    CFBridgingRetain(target);
  }
  call->invocation = inv;
  const bool main = (m->flags & kMainThread) != 0;

  if (!async) {
    if (main && ![NSThread isMainThread]) {
      dispatch_sync(dispatch_get_main_queue(), ^{
        invokeNow(*call);
      });
    } else {
      invokeNow(*call);
    }
    return outcome(rt, *call);
  }

  // Promise variant: invoke on the main queue (UIKit) or a background queue,
  // settle on the JS thread through the CallInvoker.
  auto promiseCtor = rt.global().getPropertyAsFunction(rt, "Promise");
  auto executor = jsi::Function::createFromHostFunction(
      rt,
      jsi::PropNameID::forAscii(rt, "executor"),
      2,
      [call, main](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, std::size_t) -> jsi::Value {
        auto resolveFn = std::make_shared<jsi::Value>(rt, a[0]);
        auto rejectFn = std::make_shared<jsi::Value>(rt, a[1]);
        auto invoker = gInvoker;
        dispatch_queue_t queue = main ? dispatch_get_main_queue() : dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_async(queue, ^{
          invokeNow(*call);
          invoker->invokeAsync([call, resolveFn, rejectFn](jsi::Runtime& rt) {
            try {
              auto v = outcome(rt, *call);
              resolveFn->asObject(rt).asFunction(rt).call(rt, std::move(v));
            } catch (const jsi::JSError& err) {
              rejectFn->asObject(rt).asFunction(rt).call(rt, jsi::Value(rt, err.value()));
            }
          });
        });
        return jsi::Value::undefined();
      });
  return promiseCtor.callAsConstructor(rt, executor);
}

jsi::Object makeClassObject(jsi::Runtime& rt, const ClassSpec* c) {
  jsi::Object o(rt);
  for (std::size_t i = 0; i < c->memberCount; i++) {
    const MemberSpec* m = &c->members[i];
    o.setProperty(
        rt,
        m->jsName,
        jsi::Function::createFromHostFunction(
            rt,
            jsi::PropNameID::forUtf8(rt, std::string(m->jsName)),
            1,
            [c, m](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* args, std::size_t count) {
              return callMember(rt, c, m, args, count);
            }));
  }
  return o;
}

// ------------------------------------------------------------------ root

class Root : public jsi::HostObject {
 public:
  jsi::Value get(jsi::Runtime& rt, const jsi::PropNameID& name) override {
    const std::string n = name.utf8(rt);
    auto cached = cache_.find(n);
    if (cached != cache_.end()) return jsi::Value(rt, *cached->second);
    jsi::Value v = builtin(rt, n);
    if (v.isUndefined()) {
      const ClassSpec* c = gTables.lookupClass(n);
      if (c == nullptr) return jsi::Value::undefined();
      v = jsi::Value(rt, makeClassObject(rt, c));
    }
    cache_.emplace(n, std::make_shared<jsi::Value>(rt, v));
    return v;
  }

 private:
  using V = jsi::Value;

  static jsi::Function fn(jsi::Runtime& rt, const char* name, jsi::HostFunctionType f) {
    return jsi::Function::createFromHostFunction(rt, jsi::PropNameID::forAscii(rt, name), 1, std::move(f));
  }

  static id arg(jsi::Runtime& rt, const V* a, std::size_t c, std::size_t i) {
    if (c <= i) typeError(rt, "missing argument");
    return objectArg(rt, a[i], "argument");
  }

  static std::string str(jsi::Runtime& rt, const V* a, std::size_t c, std::size_t i) {
    if (c <= i || !a[i].isString()) typeError(rt, "expected string");
    return a[i].getString(rt).utf8(rt);
  }

  jsi::Value builtin(jsi::Runtime& rt, const std::string& n) {
    if (n == "version") return jsi::String::createFromAscii(rt, "0.1.0-dev.1");
    if (n == "platform") return jsi::String::createFromAscii(rt, "ios");
    if (n == "release") {
      return fn(rt, "release", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        auto h = c > 0 ? handleOf(rt, a[0]) : nullptr;
        if (!h) typeError(rt, "release(handle)");
        if (h->released()) fail(rt, "DoubleReleaseError", "the native object was already released");
        h->release();
        return V::undefined();
      });
    }
    if (n == "isReleased") {
      return fn(rt, "isReleased", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        auto h = c > 0 ? handleOf(rt, a[0]) : nullptr;
        if (!h) typeError(rt, "isReleased(handle)");
        return V(h->released());
      });
    }
    if (n == "isKindOfClass") {
      return fn(rt, "isKindOfClass", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        Class k = objc_getClass(str(rt, a, c, 1).c_str());
        return V(o != nil && k != nil && [o isKindOfClass:k]);
      });
    }
    if (n == "conformsToProtocol") {
      return fn(rt, "conformsToProtocol", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        Protocol* p = objc_getProtocol(str(rt, a, c, 1).c_str());
        return V(o != nil && p != nil && [o conformsToProtocol:p]);
      });
    }
    if (n == "isSameObject") {
      return fn(rt, "isSameObject", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        return V(arg(rt, a, c, 0) == arg(rt, a, c, 1));
      });
    }
    if (n == "isEqual") {
      return fn(rt, "isEqual", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id x = arg(rt, a, c, 0);
        id y = arg(rt, a, c, 1);
        return V(x == y || (x != nil && [x isEqual:y]));
      });
    }
    if (n == "describe") {
      return fn(rt, "describe", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        return toJsString(rt, o == nil ? @"nil" : [o description]);
      });
    }
    if (n == "className") {
      return fn(rt, "className", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        return toJsString(rt, o == nil ? @"nil" : NSStringFromClass([o class]));
      });
    }
    if (n == "hashOf") {
      return fn(rt, "hashOf", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        return V(static_cast<double>(o == nil ? 0 : [o hash]));
      });
    }
    if (n == "classExists") {
      return fn(rt, "classExists", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        return V(objc_getClass(str(rt, a, c, 0).c_str()) != nil);
      });
    }
    if (n == "iosVersion") {
      return fn(rt, "iosVersion", [](jsi::Runtime& rt, const V&, const V*, std::size_t) -> V {
        const NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
        return jsi::String::createFromUtf8(
            rt, std::to_string(v.majorVersion) + "." + std::to_string(v.minorVersion) + "." + std::to_string(v.patchVersion));
      });
    }
    if (n == "log") {
      // Writes to the unified log (NSLog), also in release builds.
      return fn(rt, "log", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        if (c == 0) typeError(rt, "log(message)");
        NSLog(@"%@", toNSString(rt, a[0]) ?: @"");
        return V::undefined();
      });
    }
    if (n == "string") {
      // Converts an NSString handle to a JS string (null for nil).
      return fn(rt, "string", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        if (o != nil && ![o isKindOfClass:[NSString class]]) typeError(rt, "not an NSString");
        return toJsString(rt, (NSString*)o);
      });
    }
    return V::undefined();
  }

  std::unordered_map<std::string, std::shared_ptr<jsi::Value>> cache_;
};

} // namespace

void install(jsi::Runtime& rt, std::shared_ptr<CallInvoker> invoker, const Tables& tables) {
  gTables = tables;
  gInvoker = std::move(invoker);
  rt.global().setProperty(rt, "__nab", jsi::Object::createFromHostObject(rt, std::make_shared<Root>()));
}

} // namespace nab::objc
