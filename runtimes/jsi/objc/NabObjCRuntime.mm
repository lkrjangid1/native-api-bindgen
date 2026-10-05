// native-api-bindgen React Native runtime (JSI <-> Objective-C).
// Licensed under the Apache License, Version 2.0 (project source).
// Compiled with ARC (-fobjc-arc).
#import "NabObjCRuntime.h"
#import "NabObjCBlocks.h"

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <cstring>
#include <string>
#include <algorithm>
#include <atomic>
#include <mutex>
#include <thread>
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
std::thread::id gJsThread;
jsi::Runtime* gRuntime = nullptr;
// True while the JS thread waits in dispatch_sync for the main thread: a
// protocol method needing a JS result must not block the main thread then.
std::atomic<bool> gJsWaitingOnMain{false};

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
    if (*p == 'S' || *p == 'B') {
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

// ------------------------------------------------------------------ blocks

} // namespace

struct BlockTarget {
  std::shared_ptr<jsi::Value> fn; // the JS function; touched on the JS thread only
  std::string codes;              // result code, then one code per argument

  ~BlockTarget() {
    // Blocks may be deallocated on any thread; JS values die on the JS thread.
    auto f = std::move(fn);
    if (f && gInvoker) gInvoker->invokeAsync([f](jsi::Runtime&) mutable { f.reset(); });
  }
};

namespace {

jsi::Value boxedToJs(jsi::Runtime& rt, char code, id v) {
  switch (code) {
    case 'z': return jsi::Value(v != nil && [(NSNumber*)v boolValue]);
    case 'n': return jsi::Value(v == nil ? 0.0 : [(NSNumber*)v doubleValue]);
    case 'j': {
      const long long x = v == nil ? 0 : [(NSNumber*)v longLongValue];
      return gTables.longAsBigInt ? jsi::Value(jsi::BigInt::fromInt64(rt, x))
                                  : jsi::Value(static_cast<double>(x));
    }
    case 's':
      if (v == nil) return jsi::Value::null();
      if (![v isKindOfClass:[NSString class]]) return wrap(rt, v);
      return toJsString(rt, (NSString*)v);
    default: return wrap(rt, v);
  }
}

id jsToBoxed(jsi::Runtime& rt, char code, const jsi::Value& v) {
  switch (code) {
    case 'v': return nil;
    case 'z': return @(v.isBool() ? v.getBool() : toInt64(rt, v) != 0);
    case 'n': return @(toDouble(rt, v));
    case 'j': return @(toInt64(rt, v));
    case 's': return v.isString() ? toNSString(rt, v) : objectArg(rt, v, "block result");
    default: return objectArg(rt, v, "block result");
  }
}

/// Runs the JS function of [t] on the JS thread with boxed [args].
id runBlock(jsi::Runtime& rt, const BlockTarget& t, const std::vector<id>& args) {
  std::vector<jsi::Value> jsArgs;
  jsArgs.reserve(args.size());
  for (std::size_t i = 0; i < args.size() && i + 1 < t.codes.size(); i++) {
    jsArgs.push_back(boxedToJs(rt, t.codes[i + 1], args[i]));
  }
  auto fn = t.fn->asObject(rt).asFunction(rt);
  auto r = fn.call(rt, static_cast<const jsi::Value*>(jsArgs.data()), jsArgs.size());
  return jsToBoxed(rt, t.codes.empty() ? 'v' : t.codes[0], r);
}

void logBlockError(const std::string& message) {
  NSLog(@"native-api-bindgen: error in a JavaScript block: %s", message.c_str());
}

/// Wraps JS function [v] (or null) as a block of generated factory [key].
id makeBlock(jsi::Runtime& rt, const jsi::Value& v, const std::string& key, const char* selector) {
  if (v.isNull() || v.isUndefined()) return nil;
  if (!v.isObject() || !v.getObject(rt).isFunction(rt)) {
    typeError(rt, std::string("expected a function for a block argument of ") + selector);
  }
  const BlockFactory* f = gTables.lookupBlock == nullptr ? nullptr : gTables.lookupBlock(key);
  if (f == nullptr) typeError(rt, std::string("unknown block signature ") + key);
  auto target = std::make_shared<BlockTarget>();
  target->fn = std::make_shared<jsi::Value>(rt, v);
  target->codes = f->codes;
  return f->make(std::move(target));
}

} // namespace

id callBlock(const std::shared_ptr<BlockTarget>& target, std::vector<id> args) {
  if (std::this_thread::get_id() == gJsThread && gRuntime != nullptr) {
    // Synchronous (e.g. an NS_NOESCAPE block during a call from JS). JS
    // exceptions must not unwind through Objective-C frames.
    try {
      return runBlock(*gRuntime, *target, args);
    } catch (const jsi::JSError& e) {
      logBlockError(e.getMessage());
    } catch (const std::exception& e) {
      logBlockError(e.what());
    }
    return nil;
  }
  if (!target->codes.empty() && target->codes[0] != 'v') {
    NSLog(@"native-api-bindgen: a block returning a value was invoked off the JS thread; returning nil/0");
    return nil;
  }
  if (!gInvoker) return nil;
  gInvoker->invokeAsync([target, args = std::move(args)](jsi::Runtime& rt) {
    try {
      runBlock(rt, *target, args);
    } catch (const jsi::JSError& e) {
      logBlockError(e.getMessage());
    } catch (const std::exception& e) {
      logBlockError(e.what());
    }
  });
  return nil;
}

/// Owns the bytes of an ArrayBuffer copied from an NSData.
struct DataBuffer : jsi::MutableBuffer {
  explicit DataBuffer(std::size_t n) : bytes(n) {}
  std::size_t size() const override { return bytes.size(); }
  uint8_t* data() override { return bytes.data(); }
  std::vector<uint8_t> bytes;
};

// --------------------------------------------------------------- protocols

/// JS implementation of protocol methods: selector -> [codes, function].
struct ProtocolDispatcher {
  std::shared_ptr<jsi::Object> table;                 // JS thread only
  std::unordered_map<std::string, std::string> codes; // selector -> codes

  ~ProtocolDispatcher() {
    auto t = std::move(table);
    if (t && gInvoker) gInvoker->invokeAsync([t](jsi::Runtime&) mutable { t.reset(); });
  }
};

/// One forwarded protocol call: arguments captured from the NSInvocation
/// (objects retained), result written back.
struct ProtocolCall {
  std::string selector;
  std::string codes;
  std::vector<std::string> encodings; // argument type encodings
  std::vector<std::vector<uint8_t>> bytes;
  std::vector<id> objects;             // strong; nil for non-objects
  std::string retEnc;
  std::vector<uint8_t> retBytes;
  __strong id retObject = nil;
  bool failed = false;
};

namespace {

void runProtocolCall(jsi::Runtime& rt, const ProtocolDispatcher& d, ProtocolCall& c) {
  try {
    const auto codes = parseConv(c.codes.c_str());
    std::vector<jsi::Value> args;
    for (std::size_t i = 0; i < c.encodings.size(); i++) {
      const Code code = i + 1 < codes.size() ? codes[i + 1] : Code{'o', {}};
      switch (code.kind) {
        case 'o': args.push_back(wrap(rt, c.objects[i])); break;
        case 's':
          if (c.objects[i] == nil) {
            args.push_back(jsi::Value::null());
          } else if ([c.objects[i] isKindOfClass:[NSString class]]) {
            args.push_back(toJsString(rt, (NSString*)c.objects[i]));
          } else {
            args.push_back(wrap(rt, c.objects[i]));
          }
          break;
        default:
          args.push_back(readValue(rt, c.encodings[i].c_str(), c.bytes[i].data(),
                                   code.structName.empty() ? nullptr : code.structName.c_str()));
      }
    }
    auto entry = d.table->getPropertyAsObject(rt, c.selector.c_str()).asArray(rt);
    auto fn = entry.getValueAtIndex(rt, 1).asObject(rt).asFunction(rt);
    auto r = fn.call(rt, static_cast<const jsi::Value*>(args.data()), args.size());
    const char rk = codes.empty() ? 'v' : codes[0].kind;
    const char* enc = skipQualifiers(c.retEnc.c_str());
    if (rk == 'v' || *enc == 'v') return;
    if (rk == 'o') {
      c.retObject = objectArg(rt, r, c.selector.c_str());
    } else if (rk == 's') {
      c.retObject = r.isString() ? toNSString(rt, r) : objectArg(rt, r, c.selector.c_str());
    } else {
      NSUInteger size = 0;
      NSGetSizeAndAlignment(enc, &size, nullptr);
      c.retBytes.assign(size, 0);
      writeValue(rt, enc, r, c.retBytes.data(), codes[0].structName.empty() ? nullptr : codes[0].structName.c_str());
    }
  } catch (const jsi::JSError& e) {
    c.failed = true;
    NSLog(@"native-api-bindgen: error in JavaScript protocol method %s: %s", c.selector.c_str(), e.getMessage().c_str());
  } catch (const std::exception& e) {
    c.failed = true;
    NSLog(@"native-api-bindgen: error in JavaScript protocol method %s: %s", c.selector.c_str(), e.what());
  }
}

void setProtocolResult(NSInvocation* inv, ProtocolCall& c) {
  const char* enc = skipQualifiers(c.retEnc.c_str());
  if (*enc == 'v') return;
  if (*enc == '@' || *enc == '#') {
    // +0 for the caller: hand over an autoreleased reference.
    id r = c.retObject;
    if (r != nil) CFAutorelease(CFBridgingRetain(r));
    __unsafe_unretained id raw = r;
    [inv setReturnValue:&raw];
    return;
  }
  NSUInteger size = 0;
  NSGetSizeAndAlignment(enc, &size, nullptr);
  if (c.retBytes.size() < size) c.retBytes.assign(size, 0); // failed: zero
  [inv setReturnValue:c.retBytes.data()];
}

} // namespace

void forwardProtocolCall(const std::shared_ptr<ProtocolDispatcher>& d, NSInvocation* inv) {
  auto call = std::make_shared<ProtocolCall>();
  call->selector = sel_getName(inv.selector);
  auto it = d->codes.find(call->selector);
  if (it == d->codes.end()) return;
  call->codes = it->second;
  NSMethodSignature* sig = inv.methodSignature;
  call->retEnc = sig.methodReturnType;
  for (NSUInteger i = 2; i < sig.numberOfArguments; i++) {
    const char* enc = skipQualifiers([sig getArgumentTypeAtIndex:i]);
    call->encodings.emplace_back(enc);
    if (*enc == '@') {
      __unsafe_unretained id o = nil;
      [inv getArgument:&o atIndex:i];
      call->objects.push_back(o);
      call->bytes.emplace_back();
    } else {
      NSUInteger size = 0;
      NSGetSizeAndAlignment(enc, &size, nullptr);
      std::vector<uint8_t> buf(size, 0);
      [inv getArgument:buf.data() atIndex:i];
      call->objects.push_back(nil);
      call->bytes.push_back(std::move(buf));
    }
  }
  const bool isVoid = *skipQualifiers(call->retEnc.c_str()) == 'v';
  if (std::this_thread::get_id() == gJsThread && gRuntime != nullptr) {
    runProtocolCall(*gRuntime, *d, *call);
    setProtocolResult(inv, *call);
    return;
  }
  if (!gInvoker) return;
  if (isVoid) {
    gInvoker->invokeAsync([d, call](jsi::Runtime& rt) { runProtocolCall(rt, *d, *call); });
    return;
  }
  if (gJsWaitingOnMain && [NSThread isMainThread]) {
    NSLog(@"native-api-bindgen: %s needs a JavaScript result while JS waits for the main thread; returning nil/0",
          call->selector.c_str());
    call->failed = true;
    setProtocolResult(inv, *call);
    return;
  }
  // Wait for the JS thread to answer.
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  gInvoker->invokeAsync([d, call, done](jsi::Runtime& rt) {
    runProtocolCall(rt, *d, *call);
    dispatch_semaphore_signal(done);
  });
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  setProtocolResult(inv, *call);
}

} // namespace nab::objc

/// Base class of objects implementing protocols in JavaScript. A subclass per
/// protocol set adopts the protocols (class_addProtocol); calls are forwarded
/// to the JS dispatcher.
@interface NabJSProtocolObject : NSObject
@end

@implementation NabJSProtocolObject {
 @public
  std::shared_ptr<nab::objc::ProtocolDispatcher> _dispatcher;
}

- (BOOL)respondsToSelector:(SEL)sel {
  if (_dispatcher && _dispatcher->codes.count(sel_getName(sel)) > 0) return YES;
  return [super respondsToSelector:sel];
}

- (NSMethodSignature*)methodSignatureForSelector:(SEL)sel {
  NSMethodSignature* s = [super methodSignatureForSelector:sel];
  if (s != nil) return s;
  unsigned int n = 0;
  Protocol* __unsafe_unretained* protos = class_copyProtocolList([self class], &n);
  NSMethodSignature* found = nil;
  for (unsigned int i = 0; i < n && found == nil; i++) {
    for (BOOL required : {YES, NO}) {
      struct objc_method_description d = protocol_getMethodDescription(protos[i], sel, required, YES);
      if (d.types != nullptr) {
        found = [NSMethodSignature signatureWithObjCTypes:d.types];
        break;
      }
    }
  }
  free(protos);
  return found;
}

- (void)forwardInvocation:(NSInvocation*)inv {
  if (_dispatcher && _dispatcher->codes.count(sel_getName(inv.selector)) > 0) {
    nab::objc::forwardProtocolCall(_dispatcher, inv);
  } else {
    [super forwardInvocation:inv];
  }
}

@end

namespace nab::objc {
namespace {

/// Creates an object implementing [protocols] whose methods are the entries
/// of [table] (selector -> [codes, function]).
jsi::Value implementProtocols(jsi::Runtime& rt, const jsi::Array& names, const jsi::Object& table) {
  static std::mutex lock;
  static std::unordered_map<std::string, Class> classes;
  std::vector<std::string> list;
  for (std::size_t i = 0; i < names.size(rt); i++) {
    list.push_back(names.getValueAtIndex(rt, i).getString(rt).utf8(rt));
  }
  std::sort(list.begin(), list.end());
  std::string key;
  for (const auto& n : list) key += n + ",";
  Class cls = nil;
  {
    std::lock_guard<std::mutex> g(lock);
    auto it = classes.find(key);
    if (it != classes.end()) {
      cls = it->second;
    } else {
      const std::string name = "NabJSProtocolObject_" + std::to_string(classes.size() + 1);
      cls = objc_allocateClassPair([NabJSProtocolObject class], name.c_str(), 0);
      if (cls == nil) typeError(rt, "could not create a protocol class");
      for (const auto& n : list) {
        Protocol* p = objc_getProtocol(n.c_str());
        if (p == nil) {
          fail(rt, "NativeApiUnavailableError", "E010 RUNTIME_BINDING_FAILURE: protocol " + n + " is not available");
        }
        class_addProtocol(cls, p);
      }
      objc_registerClassPair(cls);
      classes.emplace(key, cls);
    }
  }
  auto d = std::make_shared<ProtocolDispatcher>();
  d->table = std::make_shared<jsi::Object>(jsi::Value(rt, table).asObject(rt));
  auto selectors = table.getPropertyNames(rt);
  for (std::size_t i = 0; i < selectors.size(rt); i++) {
    const std::string sel = selectors.getValueAtIndex(rt, i).getString(rt).utf8(rt);
    auto entry = table.getPropertyAsObject(rt, sel.c_str()).asArray(rt);
    d->codes.emplace(sel, entry.getValueAtIndex(rt, 0).getString(rt).utf8(rt));
  }
  NabJSProtocolObject* o = [[cls alloc] init];
  o->_dispatcher = std::move(d);
  return wrap(rt, o);
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
      case 'B': {
        id blk = makeBlock(rt, v, code.structName, m->selector);
        keep.push_back(blk);
        [inv setArgument:&blk atIndex:index];
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
      gJsWaitingOnMain = true;
      dispatch_sync(dispatch_get_main_queue(), ^{
        invokeNow(*call);
      });
      gJsWaitingOnMain = false;
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
    if (n == "dataFromBytes") {
      // dataFromBytes(ArrayBuffer) -> NSData handle (one copy).
      return fn(rt, "dataFromBytes", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        if (c == 0 || !a[0].isObject() || !a[0].getObject(rt).isArrayBuffer(rt)) {
          typeError(rt, "dataFromBytes(ArrayBuffer)");
        }
        auto buf = a[0].getObject(rt).getArrayBuffer(rt);
        return wrap(rt, [NSData dataWithBytes:buf.data(rt) length:buf.size(rt)]);
      });
    }
    if (n == "bytesOfData") {
      // bytesOfData(NSData handle) -> ArrayBuffer (one copy).
      return fn(rt, "bytesOfData", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        if (o == nil || ![o isKindOfClass:[NSData class]]) typeError(rt, "bytesOfData: not an NSData");
        NSData* d = (NSData*)o;
        auto buf = std::make_shared<DataBuffer>(d.length);
        if (d.length > 0) [d getBytes:buf->bytes.data() length:d.length];
        return jsi::ArrayBuffer(rt, std::move(buf));
      });
    }
    if (n == "arrayItems") {
      // arrayItems(NSArray handle) -> JS array of handles.
      return fn(rt, "arrayItems", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        id o = arg(rt, a, c, 0);
        if (o == nil || ![o isKindOfClass:[NSArray class]]) typeError(rt, "arrayItems: not an NSArray");
        NSArray* items = (NSArray*)o;
        jsi::Array out(rt, items.count);
        for (NSUInteger i = 0; i < items.count; i++) out.setValueAtIndex(rt, i, wrap(rt, items[i]));
        return jsi::Value(rt, out);
      });
    }
    if (n == "implementProtocols") {
      // implementProtocols(names: string[], table: {sel: [codes, fn]})
      return fn(rt, "implementProtocols", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        if (c < 2 || !a[0].isObject() || !a[1].isObject()) typeError(rt, "implementProtocols(names, table)");
        return implementProtocols(rt, a[0].getObject(rt).getArray(rt), a[1].getObject(rt));
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
  gJsThread = std::this_thread::get_id();
  gRuntime = &rt;
  rt.global().setProperty(rt, "__nab", jsi::Object::createFromHostObject(rt, std::make_shared<Root>()));
}

} // namespace nab::objc
