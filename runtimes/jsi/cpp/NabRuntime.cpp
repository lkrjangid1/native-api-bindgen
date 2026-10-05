// native-api-bindgen React Native runtime (JSI <-> JNI).
// Licensed under the Apache License, Version 2.0 (project source).
#include "NabRuntime.h"

#include <atomic>
#include <future>
#include <mutex>
#include <stdexcept>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace nab {
namespace {

using facebook::react::CallInvoker;

// ----------------------------------------------------------------- globals

JavaVM* gVm = nullptr;
std::atomic<bool> gLongAsBigInt{true};

// Runtime classes from the app class loader (resolved in initialize()).
jclass gHandlerClass = nullptr;     // dev.nativeapibindgen.runtime.NabInvocationHandler
jmethodID gHandlerCreate = nullptr; // static Object create(long, Class)
jclass gContextClass = nullptr;     // dev.nativeapibindgen.runtime.NabContext
jmethodID gAppContext = nullptr;
jmethodID gCurrentActivity = nullptr;
jclass gViewsClass = nullptr;          // dev.nativeapibindgen.runtime.NabViews
jmethodID gViewsRegister = nullptr;     // static long register(Object)
jmethodID gViewsUnregister = nullptr;   // static void unregister(long)
jclass gContinuationClass = nullptr;    // dev.nativeapibindgen.runtime.NabContinuation
jmethodID gContinuationCreate = nullptr; // static Object create(long)
jmethodID gContinuationIsSuspended = nullptr; // static boolean isSuspended(Object)

// Boot classes used for conversions.
struct Boot {
  jclass object, string, cls, throwable, boolean, byte, character, shortc,
      integer, longc, floatc, doublec, runtimeException, illegalState;
  jmethodID objectToString, objectHashCode, objectGetClass, classGetName,
      throwableToString, booleanValue, booleanValueOf, byteValue, byteValueOf,
      charValue, charValueOf, shortValue, shortValueOf, intValue, intValueOf,
      longValue, longValueOf, floatValue, floatValueOf, doubleValue,
      doubleValueOf;
  jclass log;
  jmethodID logStack;
};
Boot gBoot{};

// JS-thread state (set in install()).
std::thread::id gJsThread;
jsi::Runtime* gRuntime = nullptr;
std::shared_ptr<CallInvoker> gInvoker;

// ------------------------------------------------------------------ JNIEnv

struct Detacher {
  bool attached = false;
  ~Detacher() {
    if (attached && gVm != nullptr) gVm->DetachCurrentThread();
  }
};

JNIEnv* env() {
  JNIEnv* e = nullptr;
  if (gVm->GetEnv(reinterpret_cast<void**>(&e), JNI_VERSION_1_6) == JNI_OK) {
    return e;
  }
  static thread_local Detacher detacher;
#if defined(__ANDROID__)
  gVm->AttachCurrentThread(&e, nullptr); // NDK: JNIEnv**
#else
  gVm->AttachCurrentThread(reinterpret_cast<void**>(&e), nullptr); // JDK: void**
#endif
  detacher.attached = true;
  return e;
}

/// Frees all local references created inside a host call.
struct LocalFrame {
  explicit LocalFrame(JNIEnv* e, jint capacity = 64) : env(e) {
    env->PushLocalFrame(capacity);
  }
  ~LocalFrame() { env->PopLocalFrame(nullptr); }
  JNIEnv* env;
};

jclass globalClass(JNIEnv* e, const char* name) {
  jclass local = e->FindClass(name);
  if (local == nullptr) {
    e->ExceptionClear();
    return nullptr;
  }
  auto g = static_cast<jclass>(e->NewGlobalRef(local));
  e->DeleteLocalRef(local);
  return g;
}

void initBoot(JNIEnv* e) {
  auto& b = gBoot;
  b.object = globalClass(e, "java/lang/Object");
  b.string = globalClass(e, "java/lang/String");
  b.cls = globalClass(e, "java/lang/Class");
  b.throwable = globalClass(e, "java/lang/Throwable");
  b.boolean = globalClass(e, "java/lang/Boolean");
  b.byte = globalClass(e, "java/lang/Byte");
  b.character = globalClass(e, "java/lang/Character");
  b.shortc = globalClass(e, "java/lang/Short");
  b.integer = globalClass(e, "java/lang/Integer");
  b.longc = globalClass(e, "java/lang/Long");
  b.floatc = globalClass(e, "java/lang/Float");
  b.doublec = globalClass(e, "java/lang/Double");
  b.runtimeException = globalClass(e, "java/lang/RuntimeException");
  b.illegalState = globalClass(e, "java/lang/IllegalStateException");
  b.objectToString = e->GetMethodID(b.object, "toString", "()Ljava/lang/String;");
  b.objectHashCode = e->GetMethodID(b.object, "hashCode", "()I");
  b.objectGetClass = e->GetMethodID(b.object, "getClass", "()Ljava/lang/Class;");
  b.classGetName = e->GetMethodID(b.cls, "getName", "()Ljava/lang/String;");
  b.throwableToString = e->GetMethodID(b.throwable, "toString", "()Ljava/lang/String;");
  b.booleanValue = e->GetMethodID(b.boolean, "booleanValue", "()Z");
  b.booleanValueOf = e->GetStaticMethodID(b.boolean, "valueOf", "(Z)Ljava/lang/Boolean;");
  b.byteValue = e->GetMethodID(b.byte, "byteValue", "()B");
  b.byteValueOf = e->GetStaticMethodID(b.byte, "valueOf", "(B)Ljava/lang/Byte;");
  b.charValue = e->GetMethodID(b.character, "charValue", "()C");
  b.charValueOf = e->GetStaticMethodID(b.character, "valueOf", "(C)Ljava/lang/Character;");
  b.shortValue = e->GetMethodID(b.shortc, "shortValue", "()S");
  b.shortValueOf = e->GetStaticMethodID(b.shortc, "valueOf", "(S)Ljava/lang/Short;");
  b.intValue = e->GetMethodID(b.integer, "intValue", "()I");
  b.intValueOf = e->GetStaticMethodID(b.integer, "valueOf", "(I)Ljava/lang/Integer;");
  b.longValue = e->GetMethodID(b.longc, "longValue", "()J");
  b.longValueOf = e->GetStaticMethodID(b.longc, "valueOf", "(J)Ljava/lang/Long;");
  b.floatValue = e->GetMethodID(b.floatc, "floatValue", "()F");
  b.floatValueOf = e->GetStaticMethodID(b.floatc, "valueOf", "(F)Ljava/lang/Float;");
  b.doubleValue = e->GetMethodID(b.doublec, "doubleValue", "()D");
  b.doubleValueOf = e->GetStaticMethodID(b.doublec, "valueOf", "(D)Ljava/lang/Double;");
  b.log = globalClass(e, "android/util/Log");
  b.logStack = b.log == nullptr
      ? nullptr
      : e->GetStaticMethodID(b.log, "getStackTraceString", "(Ljava/lang/Throwable;)Ljava/lang/String;");
  e->ExceptionClear();
}

// ------------------------------------------------------------- strings

std::u16string javaToU16(JNIEnv* e, jstring s) {
  const jsize len = e->GetStringLength(s);
  const jchar* chars = e->GetStringChars(s, nullptr);
  std::u16string out(reinterpret_cast<const char16_t*>(chars), static_cast<std::size_t>(len));
  e->ReleaseStringChars(s, chars);
  return out;
}

std::string javaToUtf8(JNIEnv* e, jstring s) {
  if (s == nullptr) return "null";
  const char* c = e->GetStringUTFChars(s, nullptr);
  std::string out(c);
  e->ReleaseStringUTFChars(s, c);
  return out;
}

jstring jsToJava(jsi::Runtime& rt, JNIEnv* e, const jsi::String& s) {
  const std::u16string u = s.utf16(rt);
  return e->NewString(reinterpret_cast<const jchar*>(u.data()), static_cast<jsize>(u.size()));
}

jsi::Value javaStringToJs(jsi::Runtime& rt, JNIEnv* e, jstring s) {
  if (s == nullptr) return jsi::Value::null();
  return jsi::String::createFromUtf16(rt, javaToU16(e, s));
}

// ------------------------------------------------------------- handles

/// A JS-owned reference to a Java object. Released when the JS object is
/// garbage-collected or explicitly via `__nab.release(h)`.
class Handle : public jsi::HostObject {
 public:
  explicit Handle(jobject global) : ref_(global) {}
  ~Handle() override { release(); }

  jobject ref(jsi::Runtime& rt) const {
    if (ref_ == nullptr) {
      throw jsi::JSError(rt, "UseAfterReleaseError: the native object was released");
    }
    return ref_;
  }
  bool released() const { return ref_ == nullptr; }
  void release() {
    if (ref_ != nullptr && gVm != nullptr) {
      env()->DeleteGlobalRef(ref_);
    }
    ref_ = nullptr;
  }

 private:
  jobject ref_;
};

jsi::Value wrapObject(jsi::Runtime& rt, JNIEnv* e, jobject local) {
  if (local == nullptr) return jsi::Value::null();
  jobject g = e->NewGlobalRef(local);
  return jsi::Object::createFromHostObject(rt, std::make_shared<Handle>(g));
}

std::shared_ptr<Handle> handleOf(jsi::Runtime& rt, const jsi::Value& v) {
  if (!v.isObject()) return nullptr;
  auto o = v.getObject(rt);
  if (!o.isHostObject<Handle>(rt)) return nullptr;
  return o.getHostObject<Handle>(rt);
}

// ------------------------------------------------------------- errors

struct JavaErrorInfo {
  std::string className, message, stack;
};

JavaErrorInfo describe(JNIEnv* e, jthrowable t) {
  JavaErrorInfo info;
  auto cls = static_cast<jobject>(e->CallObjectMethod(t, gBoot.objectGetClass));
  info.className = javaToUtf8(e, static_cast<jstring>(e->CallObjectMethod(cls, gBoot.classGetName)));
  info.message = javaToUtf8(e, static_cast<jstring>(e->CallObjectMethod(t, gBoot.throwableToString)));
  if (gBoot.logStack != nullptr) {
    info.stack = javaToUtf8(e, static_cast<jstring>(e->CallStaticObjectMethod(gBoot.log, gBoot.logStack, t)));
  }
  e->ExceptionClear();
  return info;
}

jsi::Value makeJsError(jsi::Runtime& rt, const JavaErrorInfo& info) {
  auto ctor = rt.global().getPropertyAsFunction(rt, "Error");
  auto err = ctor.callAsConstructor(rt, jsi::String::createFromUtf8(rt, info.message)).asObject(rt);
  err.setProperty(rt, "name", "NativeJavaError");
  err.setProperty(rt, "nativeClassName", jsi::String::createFromUtf8(rt, info.className));
  err.setProperty(rt, "javaStackTrace", jsi::String::createFromUtf8(rt, info.stack));
  return jsi::Value(rt, err);
}

/// Throws a JS error if a Java exception is pending.
void check(jsi::Runtime& rt, JNIEnv* e) {
  if (!e->ExceptionCheck()) return;
  auto t = e->ExceptionOccurred();
  e->ExceptionClear();
  auto info = describe(e, t);
  e->DeleteLocalRef(t);
  throw jsi::JSError(rt, makeJsError(rt, info));
}

[[noreturn]] void typeError(jsi::Runtime& rt, const std::string& msg) {
  throw jsi::JSError(rt, "TypeError: " + msg);
}

// ------------------------------------------------------------- descriptors

/// Splits a JNI method descriptor into parameter and return descriptors.
struct Signature {
  std::vector<std::string> params;
  std::string ret;
};

std::size_t typeEnd(const std::string& d, std::size_t i) {
  while (d[i] == '[') ++i;
  if (d[i] == 'L') return d.find(';', i) + 1;
  return i + 1;
}

Signature parseMethod(const std::string& d) {
  Signature s;
  std::size_t i = 1;
  while (d[i] != ')') {
    const auto end = typeEnd(d, i);
    s.params.push_back(d.substr(i, end - i));
    i = end;
  }
  s.ret = d.substr(i + 1);
  return s;
}

std::string internalOf(const std::string& objDesc) {
  // "Lpkg/Name;" -> "pkg/Name"; arrays keep descriptor form for FindClass.
  if (objDesc[0] == 'L') return objDesc.substr(1, objDesc.size() - 2);
  return objDesc;
}

// ------------------------------------------------------------- JS -> Java

double number(jsi::Runtime& rt, const jsi::Value& v, const char* what) {
  if (!v.isNumber()) typeError(rt, std::string("expected number for ") + what);
  return v.getNumber();
}

jlong toLong(jsi::Runtime& rt, const jsi::Value& v) {
  if (v.isBigInt()) return static_cast<jlong>(v.getBigInt(rt).asInt64(rt));
  if (v.isNumber()) return static_cast<jlong>(v.getNumber());
  typeError(rt, "expected bigint or number for long");
}

jobject toJavaObject(jsi::Runtime& rt, JNIEnv* e, const jsi::Value& v, const std::string& desc);

/// Owns the bytes of an ArrayBuffer created from a Java byte[].
struct ByteVectorBuffer : jsi::MutableBuffer {
  explicit ByteVectorBuffer(std::size_t n) : bytes(n) {}
  std::size_t size() const override { return bytes.size(); }
  uint8_t* data() override { return bytes.data(); }
  std::vector<uint8_t> bytes;
};

jarray toJavaArray(jsi::Runtime& rt, JNIEnv* e, const jsi::Value& v, const std::string& desc) {
  if (desc == "[B" && v.isObject() && v.getObject(rt).isArrayBuffer(rt)) {
    // Fast path: one region copy from the ArrayBuffer.
    auto buf = v.getObject(rt).getArrayBuffer(rt);
    const auto n = static_cast<jsize>(buf.size(rt));
    auto a = e->NewByteArray(n);
    if (n > 0) e->SetByteArrayRegion(a, 0, n, reinterpret_cast<const jbyte*>(buf.data(rt)));
    return a;
  }
  if (!v.isObject() || !v.getObject(rt).isArray(rt)) {
    if (auto h = handleOf(rt, v)) return static_cast<jarray>(e->NewLocalRef(h->ref(rt)));
    typeError(rt, "expected array for " + desc);
  }
  auto arr = v.getObject(rt).getArray(rt);
  const auto n = static_cast<jsize>(arr.size(rt));
  const std::string elem = desc.substr(1);
  auto num = [&](jsize i) { return number(rt, arr.getValueAtIndex(rt, i), "array element"); };
  switch (elem[0]) {
    case 'Z': {
      auto a = e->NewBooleanArray(n);
      for (jsize i = 0; i < n; i++) {
        jboolean x = arr.getValueAtIndex(rt, i).getBool() ? JNI_TRUE : JNI_FALSE;
        e->SetBooleanArrayRegion(a, i, 1, &x);
      }
      return a;
    }
#define NAB_PRIM_ARRAY(CH, JT, NEW, SET)                       \
  case CH: {                                                   \
    auto a = e->NEW(n);                                        \
    for (jsize i = 0; i < n; i++) {                            \
      JT x = static_cast<JT>(num(i));                          \
      e->SET(a, i, 1, &x);                                     \
    }                                                          \
    return a;                                                  \
  }
      NAB_PRIM_ARRAY('B', jbyte, NewByteArray, SetByteArrayRegion)
      NAB_PRIM_ARRAY('C', jchar, NewCharArray, SetCharArrayRegion)
      NAB_PRIM_ARRAY('S', jshort, NewShortArray, SetShortArrayRegion)
      NAB_PRIM_ARRAY('I', jint, NewIntArray, SetIntArrayRegion)
      NAB_PRIM_ARRAY('F', jfloat, NewFloatArray, SetFloatArrayRegion)
      NAB_PRIM_ARRAY('D', jdouble, NewDoubleArray, SetDoubleArrayRegion)
#undef NAB_PRIM_ARRAY
    case 'J': {
      auto a = e->NewLongArray(n);
      for (jsize i = 0; i < n; i++) {
        jlong x = toLong(rt, arr.getValueAtIndex(rt, i));
        e->SetLongArrayRegion(a, i, 1, &x);
      }
      return a;
    }
    default: {
      jclass ec = e->FindClass(internalOf(elem).c_str());
      check(rt, e);
      auto a = e->NewObjectArray(n, ec, nullptr);
      for (jsize i = 0; i < n; i++) {
        jobject x = toJavaObject(rt, e, arr.getValueAtIndex(rt, i), elem);
        e->SetObjectArrayElement(a, i, x);
        e->DeleteLocalRef(x);
      }
      return a;
    }
  }
}

/// Converts a JS value to a *local* Java reference for an object descriptor.
jobject toJavaObject(jsi::Runtime& rt, JNIEnv* e, const jsi::Value& v, const std::string& desc) {
  if (v.isNull() || v.isUndefined()) return nullptr;
  if (desc[0] == '[') return toJavaArray(rt, e, v, desc);
  if (v.isString()) {
    // Strings are accepted wherever a String, CharSequence or Object is expected.
    return jsToJava(rt, e, v.getString(rt));
  }
  if (auto h = handleOf(rt, v)) return e->NewLocalRef(h->ref(rt));
  typeError(rt, "expected a native object handle for " + desc);
}

jvalue toJvalue(jsi::Runtime& rt, JNIEnv* e, const jsi::Value& v, const std::string& desc) {
  jvalue j{};
  switch (desc[0]) {
    case 'Z':
      if (!v.isBool()) typeError(rt, "expected boolean");
      j.z = v.getBool() ? JNI_TRUE : JNI_FALSE;
      break;
    case 'B': j.b = static_cast<jbyte>(number(rt, v, "byte")); break;
    case 'C': j.c = static_cast<jchar>(number(rt, v, "char")); break;
    case 'S': j.s = static_cast<jshort>(number(rt, v, "short")); break;
    case 'I': j.i = static_cast<jint>(number(rt, v, "int")); break;
    case 'J': j.j = toLong(rt, v); break;
    case 'F': j.f = static_cast<jfloat>(number(rt, v, "float")); break;
    case 'D': j.d = number(rt, v, "double"); break;
    default: j.l = toJavaObject(rt, e, v, desc); break;
  }
  return j;
}

// ------------------------------------------------------------- Java -> JS

jsi::Value longToJs(jsi::Runtime& rt, jlong x) {
  if (gLongAsBigInt) return jsi::BigInt::fromInt64(rt, x);
  return jsi::Value(static_cast<double>(x));
}

jsi::Value objectToJs(jsi::Runtime& rt, JNIEnv* e, jobject o, const std::string& desc) {
  if (o == nullptr) return jsi::Value::null();
  if (desc == "Ljava/lang/String;") return javaStringToJs(rt, e, static_cast<jstring>(o));
  if (desc[0] != '[') return wrapObject(rt, e, o);
  auto a = static_cast<jarray>(o);
  const jsize n = e->GetArrayLength(a);
  if (desc == "[B") {
    // byte[] -> ArrayBuffer (one region copy; the TS side views it as Uint8Array).
    auto buf = std::make_shared<ByteVectorBuffer>(static_cast<std::size_t>(n));
    if (n > 0) e->GetByteArrayRegion(static_cast<jbyteArray>(a), 0, n, reinterpret_cast<jbyte*>(buf->bytes.data()));
    return jsi::ArrayBuffer(rt, std::move(buf));
  }
  jsi::Array out(rt, static_cast<std::size_t>(n));
  const char el = desc[1];
#define NAB_FROM_ARRAY(CH, JT, GET, CONV)                         \
  case CH: {                                                      \
    std::vector<JT> buf(static_cast<std::size_t>(n));             \
    e->GET(static_cast<JT##Array>(a), 0, n, buf.data());          \
    for (jsize i = 0; i < n; i++) out.setValueAtIndex(rt, i, CONV); \
    return jsi::Value(rt, out);                                   \
  }
  switch (el) {
    NAB_FROM_ARRAY('Z', jboolean, GetBooleanArrayRegion, jsi::Value(buf[i] == JNI_TRUE))
    NAB_FROM_ARRAY('B', jbyte, GetByteArrayRegion, jsi::Value(static_cast<double>(buf[i])))
    NAB_FROM_ARRAY('C', jchar, GetCharArrayRegion, jsi::Value(static_cast<double>(buf[i])))
    NAB_FROM_ARRAY('S', jshort, GetShortArrayRegion, jsi::Value(static_cast<double>(buf[i])))
    NAB_FROM_ARRAY('I', jint, GetIntArrayRegion, jsi::Value(static_cast<double>(buf[i])))
    NAB_FROM_ARRAY('J', jlong, GetLongArrayRegion, longToJs(rt, buf[i]))
    NAB_FROM_ARRAY('F', jfloat, GetFloatArrayRegion, jsi::Value(static_cast<double>(buf[i])))
    NAB_FROM_ARRAY('D', jdouble, GetDoubleArrayRegion, jsi::Value(buf[i]))
    default: {
      const std::string elemDesc = desc.substr(1);
      for (jsize i = 0; i < n; i++) {
        jobject x = e->GetObjectArrayElement(static_cast<jobjectArray>(a), i);
        out.setValueAtIndex(rt, i, objectToJs(rt, e, x, elemDesc));
        e->DeleteLocalRef(x);
      }
      return jsi::Value(rt, out);
    }
  }
#undef NAB_FROM_ARRAY
}

jsi::Value jvalueToJs(jsi::Runtime& rt, JNIEnv* e, const jvalue& v, const std::string& desc) {
  switch (desc[0]) {
    case 'V': return jsi::Value::undefined();
    case 'Z': return jsi::Value(v.z == JNI_TRUE);
    case 'B': return jsi::Value(static_cast<double>(v.b));
    case 'C': return jsi::Value(static_cast<double>(v.c));
    case 'S': return jsi::Value(static_cast<double>(v.s));
    case 'I': return jsi::Value(static_cast<double>(v.i));
    case 'J': return longToJs(rt, v.j);
    case 'F': return jsi::Value(static_cast<double>(v.f));
    case 'D': return jsi::Value(v.d);
    default: return objectToJs(rt, e, v.l, desc);
  }
}

// ------------------------------------------------------------- invocation

struct Resolved {
  jclass cls = nullptr;
  jmethodID mid = nullptr;
  jfieldID fid = nullptr;
  Signature sig; // for fields: params empty, ret = field descriptor
};

std::mutex gResolveMutex;
std::unordered_map<const MemberSpec*, Resolved> gResolved;
std::unordered_map<const ClassSpec*, jclass> gClasses;

const Resolved& resolve(jsi::Runtime& rt, JNIEnv* e, const ClassSpec* c, const MemberSpec* m) {
  std::lock_guard<std::mutex> lock(gResolveMutex);
  auto it = gResolved.find(m);
  if (it != gResolved.end()) return it->second;
  jclass cls;
  auto ci = gClasses.find(c);
  if (ci != gClasses.end()) {
    cls = ci->second;
  } else {
    cls = globalClass(e, c->internalName);
    if (cls == nullptr) {
      throw jsi::JSError(rt, std::string("E010 RUNTIME_BINDING_FAILURE: class not found: ") + c->key);
    }
    gClasses[c] = cls;
  }
  Resolved r;
  r.cls = cls;
  switch (m->kind) {
    case MemberKind::Constructor:
    case MemberKind::InstanceMethod:
      r.mid = e->GetMethodID(cls, m->javaName, m->descriptor);
      r.sig = parseMethod(m->descriptor);
      break;
    case MemberKind::StaticMethod:
      r.mid = e->GetStaticMethodID(cls, m->javaName, m->descriptor);
      r.sig = parseMethod(m->descriptor);
      break;
    case MemberKind::StaticGetter:
    case MemberKind::StaticSetter:
      r.fid = e->GetStaticFieldID(cls, m->javaName, m->descriptor);
      r.sig.ret = m->descriptor;
      break;
    case MemberKind::InstanceGetter:
    case MemberKind::InstanceSetter:
      r.fid = e->GetFieldID(cls, m->javaName, m->descriptor);
      r.sig.ret = m->descriptor;
      break;
  }
  if (e->ExceptionCheck() || (r.mid == nullptr && r.fid == nullptr)) {
    e->ExceptionClear();
    throw jsi::JSError(
        rt,
        std::string("E010 RUNTIME_BINDING_FAILURE: ") + c->key + "#" + m->javaName + m->descriptor +
            " not found on this device");
  }
  return gResolved.emplace(m, std::move(r)).first->second;
}

/// Result of a JNI call, independent of the JS runtime.
struct CallResult {
  jvalue value{};          // primitives; .l is a *global* ref for objects
  bool failed = false;
  JavaErrorInfo error;
};

CallResult invokeJni(JNIEnv* e, const MemberSpec* m, const Resolved& r, jobject self, const std::vector<jvalue>& args) {
  CallResult out;
  const jvalue* a = args.empty() ? nullptr : args.data();
  const char k = m->kind == MemberKind::Constructor ? 'L' : r.sig.ret[0];
  const bool isStatic = m->kind == MemberKind::StaticMethod || m->kind == MemberKind::StaticGetter ||
      m->kind == MemberKind::StaticSetter;
  jobject obj = nullptr;
  switch (m->kind) {
    case MemberKind::Constructor:
      obj = e->NewObjectA(r.cls, r.mid, a);
      break;
    case MemberKind::StaticMethod:
    case MemberKind::InstanceMethod:
      switch (k) {
#define NAB_CALL(CH, FIELD, NAME)                                                     \
  case CH:                                                                           \
    out.value.FIELD = isStatic ? e->CallStatic##NAME##MethodA(r.cls, r.mid, a)        \
                               : e->Call##NAME##MethodA(self, r.mid, a);             \
    break;
        NAB_CALL('Z', z, Boolean)
        NAB_CALL('B', b, Byte)
        NAB_CALL('C', c, Char)
        NAB_CALL('S', s, Short)
        NAB_CALL('I', i, Int)
        NAB_CALL('J', j, Long)
        NAB_CALL('F', f, Float)
        NAB_CALL('D', d, Double)
#undef NAB_CALL
        case 'V':
          if (isStatic) {
            e->CallStaticVoidMethodA(r.cls, r.mid, a);
          } else {
            e->CallVoidMethodA(self, r.mid, a);
          }
          break;
        default:
          obj = isStatic ? e->CallStaticObjectMethodA(r.cls, r.mid, a) : e->CallObjectMethodA(self, r.mid, a);
      }
      break;
    case MemberKind::StaticGetter:
    case MemberKind::InstanceGetter:
      switch (k) {
#define NAB_GET(CH, FIELD, NAME)                                                   \
  case CH:                                                                        \
    out.value.FIELD = isStatic ? e->GetStatic##NAME##Field(r.cls, r.fid)           \
                               : e->Get##NAME##Field(self, r.fid);                \
    break;
        NAB_GET('Z', z, Boolean)
        NAB_GET('B', b, Byte)
        NAB_GET('C', c, Char)
        NAB_GET('S', s, Short)
        NAB_GET('I', i, Int)
        NAB_GET('J', j, Long)
        NAB_GET('F', f, Float)
        NAB_GET('D', d, Double)
#undef NAB_GET
        default:
          obj = isStatic ? e->GetStaticObjectField(r.cls, r.fid) : e->GetObjectField(self, r.fid);
      }
      break;
    case MemberKind::StaticSetter:
    case MemberKind::InstanceSetter: {
      const jvalue& v = args.at(0);
      switch (k) {
#define NAB_SET(CH, FIELD, NAME)                                                     \
  case CH:                                                                          \
    if (isStatic) {                                                                 \
      e->SetStatic##NAME##Field(r.cls, r.fid, v.FIELD);                             \
    } else {                                                                        \
      e->Set##NAME##Field(self, r.fid, v.FIELD);                                    \
    }                                                                               \
    break;
        NAB_SET('Z', z, Boolean)
        NAB_SET('B', b, Byte)
        NAB_SET('C', c, Char)
        NAB_SET('S', s, Short)
        NAB_SET('I', i, Int)
        NAB_SET('J', j, Long)
        NAB_SET('F', f, Float)
        NAB_SET('D', d, Double)
        NAB_SET('L', l, Object)
        NAB_SET('[', l, Object)
#undef NAB_SET
      }
      break;
    }
  }
  if (e->ExceptionCheck()) {
    auto t = e->ExceptionOccurred();
    e->ExceptionClear();
    out.failed = true;
    out.error = describe(e, t);
    e->DeleteLocalRef(t);
    if (obj != nullptr) e->DeleteLocalRef(obj);
    return out;
  }
  if (obj != nullptr) {
    out.value.l = e->NewGlobalRef(obj);
    e->DeleteLocalRef(obj);
  } else if (k == 'L' || k == '[') {
    out.value.l = nullptr;
  }
  return out;
}

std::string returnDescriptor(const MemberSpec* m, const Resolved& r) {
  if (m->kind == MemberKind::Constructor) return "L" + std::string("?") + ";";
  if (m->kind == MemberKind::StaticSetter || m->kind == MemberKind::InstanceSetter) return "V";
  return r.sig.ret;
}

jsi::Value resultToJs(jsi::Runtime& rt, JNIEnv* e, CallResult& res, const std::string& retDesc) {
  if (res.failed) throw jsi::JSError(rt, makeJsError(rt, res.error));
  const bool isObject = retDesc[0] == 'L' || retDesc[0] == '[';
  jsi::Value out = jvalueToJs(rt, e, res.value, retDesc);
  if (isObject && res.value.l != nullptr) e->DeleteGlobalRef(res.value.l);
  return out;
}

// ------------------------------------------------------- Kotlin suspend

jsi::Value boxedToJs(jsi::Runtime& rt, JNIEnv* e, jobject o);

struct PendingSuspend {
  std::shared_ptr<jsi::Value> resolve; // touched only on the JS thread
  std::shared_ptr<jsi::Value> reject;
};

std::mutex gSuspendMutex;
std::unordered_map<jlong, PendingSuspend> gSuspended;
std::atomic<jlong> gNextSuspend{1};

/// Removes and returns the pending call [id] (empty if unknown).
PendingSuspend takeSuspended(jlong id) {
  std::lock_guard<std::mutex> lock(gSuspendMutex);
  auto it = gSuspended.find(id);
  if (it == gSuspended.end()) return {};
  PendingSuspend p = std::move(it->second);
  gSuspended.erase(it);
  return p;
}

/// Calls a suspend function on the JS thread with a NabContinuation. A direct
/// result settles the promise at once; COROUTINE_SUSPENDED leaves it pending
/// until resume0/fail0 (any thread) post the outcome to the JS thread.
jsi::Value callSuspend(jsi::Runtime& rt, const MemberSpec* m, const Resolved& r, jobject self, std::vector<jvalue> jargs) {
  if (gContinuationClass == nullptr) {
    throw jsi::JSError(rt, "E010 RUNTIME_BINDING_FAILURE: NabContinuation not found (call nab::initialize from JNI_OnLoad)");
  }
  auto promiseCtor = rt.global().getPropertyAsFunction(rt, "Promise");
  const Resolved* rp = &r;
  auto executor = jsi::Function::createFromHostFunction(
      rt,
      jsi::PropNameID::forAscii(rt, "executor"),
      2,
      [m, rp, self, jargs](jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, std::size_t) mutable -> jsi::Value {
        auto resolveFn = std::make_shared<jsi::Value>(rt, a[0]);
        auto rejectFn = std::make_shared<jsi::Value>(rt, a[1]);
        JNIEnv* e = env();
        LocalFrame frame(e);
        const jlong id = gNextSuspend++;
        {
          std::lock_guard<std::mutex> lock(gSuspendMutex);
          gSuspended.emplace(id, PendingSuspend{resolveFn, rejectFn});
        }
        jobject cont = e->CallStaticObjectMethod(gContinuationClass, gContinuationCreate, id);
        if (e->ExceptionCheck()) {
          auto t = e->ExceptionOccurred();
          e->ExceptionClear();
          takeSuspended(id);
          rejectFn->asObject(rt).asFunction(rt).call(rt, makeJsError(rt, describe(e, t)));
          return jsi::Value::undefined();
        }
        jvalue c;
        c.l = cont;
        jargs.push_back(c);
        CallResult res = invokeJni(e, m, *rp, self, jargs);
        if (res.failed) {
          takeSuspended(id);
          rejectFn->asObject(rt).asFunction(rt).call(rt, makeJsError(rt, res.error));
          return jsi::Value::undefined();
        }
        jobject value = res.value.l;
        const bool suspended = e->CallStaticBooleanMethod(gContinuationClass, gContinuationIsSuspended, value) == JNI_TRUE;
        if (!suspended) {
          takeSuspended(id);
          try {
            auto v = boxedToJs(rt, e, value);
            resolveFn->asObject(rt).asFunction(rt).call(rt, std::move(v));
          } catch (const jsi::JSError& err) {
            rejectFn->asObject(rt).asFunction(rt).call(rt, jsi::Value(rt, err.value()));
          }
        }
        if (value != nullptr) e->DeleteGlobalRef(value);
        return jsi::Value::undefined();
      });
  return promiseCtor.callAsConstructor(rt, executor);
}

void JNICALL resume0(JNIEnv* e, jclass, jlong id, jobject value) {
  jobject g = value == nullptr ? nullptr : e->NewGlobalRef(value);
  gInvoker->invokeAsync([id, g](jsi::Runtime& rt) {
    JNIEnv* je = env();
    LocalFrame frame(je);
    PendingSuspend p = takeSuspended(id);
    if (p.resolve) {
      try {
        auto v = boxedToJs(rt, je, g);
        p.resolve->asObject(rt).asFunction(rt).call(rt, std::move(v));
      } catch (const jsi::JSError& err) {
        p.reject->asObject(rt).asFunction(rt).call(rt, jsi::Value(rt, err.value()));
      }
    }
    if (g != nullptr) je->DeleteGlobalRef(g);
  });
}

void JNICALL fail0(JNIEnv* e, jclass, jlong id, jthrowable error) {
  JavaErrorInfo info = describe(e, error);
  gInvoker->invokeAsync([id, info](jsi::Runtime& rt) {
    PendingSuspend p = takeSuspended(id);
    if (p.reject) p.reject->asObject(rt).asFunction(rt).call(rt, makeJsError(rt, info));
  });
}

/// Host-function body shared by every generated member.
/// JS calling convention: (async: boolean, [self], ...args).
jsi::Value callMember(jsi::Runtime& rt, const ClassSpec* c, const MemberSpec* m, const jsi::Value* args, std::size_t count) {
  JNIEnv* e = env();
  LocalFrame frame(e);
  const Resolved& r = resolve(rt, e, c, m);
  const bool async = count > 0 && args[0].isBool() && args[0].getBool();
  // Kotlin suspend function: (2, [self], ...args) -> Promise; the runtime
  // supplies the trailing kotlin.coroutines.Continuation.
  const bool suspend = count > 0 && args[0].isNumber() && args[0].getNumber() == 2;
  std::size_t i = 1;
  const bool needsSelf = m->kind == MemberKind::InstanceMethod || m->kind == MemberKind::InstanceGetter ||
      m->kind == MemberKind::InstanceSetter;
  jobject self = nullptr;
  if (needsSelf) {
    if (count <= i) typeError(rt, "missing receiver");
    auto h = handleOf(rt, args[i]);
    if (!h) typeError(rt, std::string("receiver is not a native object for ") + m->jsName);
    self = h->ref(rt);
    i++;
  }
  std::vector<std::string> paramDescs = r.sig.params;
  if (m->kind == MemberKind::StaticSetter || m->kind == MemberKind::InstanceSetter) {
    paramDescs = {r.sig.ret};
  }
  if (suspend) {
    if (paramDescs.empty() || paramDescs.back() != "Lkotlin/coroutines/Continuation;") {
      typeError(rt, std::string(m->jsName) + " is not a Kotlin suspend function");
    }
    paramDescs.pop_back();
  }
  if (count - i < paramDescs.size()) {
    typeError(rt, std::string("not enough arguments for ") + m->jsName);
  }
  std::vector<jvalue> jargs;
  jargs.reserve(paramDescs.size());
  for (std::size_t p = 0; p < paramDescs.size(); p++) {
    jargs.push_back(toJvalue(rt, e, args[i + p], paramDescs[p]));
  }
  const std::string retDesc = returnDescriptor(m, r);

  if (suspend) return callSuspend(rt, m, r, self, std::move(jargs));

  if (!async) {
    CallResult res = invokeJni(e, m, r, self, jargs);
    return resultToJs(rt, e, res, retDesc);
  }

  // Asynchronous: promote references to globals, run JNI on a worker thread,
  // settle the promise on the JS thread via the CallInvoker.
  std::vector<jobject> globals;
  jobject gSelf = self == nullptr ? nullptr : e->NewGlobalRef(self);
  for (std::size_t p = 0; p < paramDescs.size(); p++) {
    const char k = paramDescs[p][0];
    if ((k == 'L' || k == '[') && jargs[p].l != nullptr) {
      jargs[p].l = e->NewGlobalRef(jargs[p].l);
      globals.push_back(jargs[p].l);
    }
  }
  auto promiseCtor = rt.global().getPropertyAsFunction(rt, "Promise");
  const Resolved* rp = &r;
  auto executor = jsi::Function::createFromHostFunction(
      rt,
      jsi::PropNameID::forAscii(rt, "executor"),
      2,
      [m, rp, gSelf, jargs, globals, retDesc](
          jsi::Runtime& rt, const jsi::Value&, const jsi::Value* a, std::size_t) -> jsi::Value {
        auto resolveFn = std::make_shared<jsi::Value>(rt, a[0]);
        auto rejectFn = std::make_shared<jsi::Value>(rt, a[1]);
        auto invoker = gInvoker;
        std::thread([m, rp, gSelf, jargs, globals, retDesc, resolveFn, rejectFn, invoker]() mutable {
          JNIEnv* we = env();
          CallResult res = invokeJni(we, m, *rp, gSelf, jargs);
          for (auto g : globals) we->DeleteGlobalRef(g);
          if (gSelf != nullptr) we->DeleteGlobalRef(gSelf);
          invoker->invokeAsync([res = std::move(res), retDesc, resolveFn = std::move(resolveFn),
                                rejectFn = std::move(rejectFn)](jsi::Runtime& rt) mutable {
            JNIEnv* je = env();
            if (res.failed) {
              rejectFn->asObject(rt).asFunction(rt).call(rt, makeJsError(rt, res.error));
              return;
            }
            try {
              auto v = resultToJs(rt, je, res, retDesc);
              resolveFn->asObject(rt).asFunction(rt).call(rt, std::move(v));
            } catch (const jsi::JSError& err) {
              rejectFn->asObject(rt).asFunction(rt).call(rt, jsi::Value(rt, err.value()));
            }
          });
        }).detach();
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

// ------------------------------------------------------------- callbacks

struct Callback {
  std::shared_ptr<jsi::Object> dispatcher; // touched only on the JS thread
  std::unordered_set<std::string> async;
};

std::mutex gCallbackMutex;
std::unordered_map<jlong, Callback> gCallbacks;
std::atomic<jlong> gNextCallback{1};

jsi::Value boxedToJs(jsi::Runtime& rt, JNIEnv* e, jobject o) {
  if (o == nullptr) return jsi::Value::null();
  auto& b = gBoot;
  if (e->IsInstanceOf(o, b.string)) return javaStringToJs(rt, e, static_cast<jstring>(o));
  if (e->IsInstanceOf(o, b.boolean)) return jsi::Value(e->CallBooleanMethod(o, b.booleanValue) == JNI_TRUE);
  if (e->IsInstanceOf(o, b.integer)) return jsi::Value(static_cast<double>(e->CallIntMethod(o, b.intValue)));
  if (e->IsInstanceOf(o, b.longc)) return longToJs(rt, e->CallLongMethod(o, b.longValue));
  if (e->IsInstanceOf(o, b.doublec)) return jsi::Value(e->CallDoubleMethod(o, b.doubleValue));
  if (e->IsInstanceOf(o, b.floatc)) return jsi::Value(static_cast<double>(e->CallFloatMethod(o, b.floatValue)));
  if (e->IsInstanceOf(o, b.shortc)) return jsi::Value(static_cast<double>(e->CallShortMethod(o, b.shortValue)));
  if (e->IsInstanceOf(o, b.byte)) return jsi::Value(static_cast<double>(e->CallByteMethod(o, b.byteValue)));
  if (e->IsInstanceOf(o, b.character)) return jsi::Value(static_cast<double>(e->CallCharMethod(o, b.charValue)));
  return wrapObject(rt, e, o);
}

/// Boxes a JS callback result as a Java object per the return descriptor.
jobject jsToBoxed(jsi::Runtime& rt, JNIEnv* e, const jsi::Value& v, const std::string& ret) {
  auto& b = gBoot;
  switch (ret[0]) {
    case 'V': return nullptr;
    case 'Z': return e->CallStaticObjectMethod(b.boolean, b.booleanValueOf, static_cast<jboolean>(v.isBool() && v.getBool()));
    case 'B': return e->CallStaticObjectMethod(b.byte, b.byteValueOf, static_cast<jbyte>(number(rt, v, "byte")));
    case 'C': return e->CallStaticObjectMethod(b.character, b.charValueOf, static_cast<jchar>(number(rt, v, "char")));
    case 'S': return e->CallStaticObjectMethod(b.shortc, b.shortValueOf, static_cast<jshort>(number(rt, v, "short")));
    case 'I': return e->CallStaticObjectMethod(b.integer, b.intValueOf, static_cast<jint>(number(rt, v, "int")));
    case 'J': return e->CallStaticObjectMethod(b.longc, b.longValueOf, toLong(rt, v));
    case 'F': return e->CallStaticObjectMethod(b.floatc, b.floatValueOf, static_cast<jfloat>(number(rt, v, "float")));
    case 'D': return e->CallStaticObjectMethod(b.doublec, b.doubleValueOf, number(rt, v, "double"));
    default: return toJavaObject(rt, e, v, ret);
  }
}

struct Outcome {
  jobject result = nullptr; // global ref
  bool failed = false;
  std::string error;
};

/// Calls the JS dispatcher on the JS thread. [args] is a global ref (or null).
Outcome dispatch(jsi::Runtime& rt, const std::shared_ptr<jsi::Object>& dispatcher, const std::string& desc, jobjectArray args) {
  JNIEnv* e = env();
  LocalFrame frame(e);
  Outcome out;
  try {
    const jsize n = args == nullptr ? 0 : e->GetArrayLength(args);
    std::vector<jsi::Value> jsArgs;
    jsArgs.reserve(static_cast<std::size_t>(n));
    for (jsize i = 0; i < n; i++) {
      jsArgs.push_back(boxedToJs(rt, e, e->GetObjectArrayElement(args, i)));
    }
    auto fn = dispatcher->getProperty(rt, desc.c_str());
    if (!fn.isObject() || !fn.getObject(rt).isFunction(rt)) {
      throw jsi::JSError(rt, "E004 UNSUPPORTED_CALLBACK: no JS implementation for " + desc);
    }
    auto r = fn.getObject(rt).getFunction(rt).call(rt, static_cast<const jsi::Value*>(jsArgs.data()), jsArgs.size());
    const std::string ret = desc.substr(desc.find(')') + 1);
    jobject boxed = jsToBoxed(rt, e, r, ret);
    out.result = boxed == nullptr ? nullptr : e->NewGlobalRef(boxed);
  } catch (const jsi::JSError& err) {
    out.failed = true;
    out.error = err.getMessage();
  } catch (const std::exception& err) {
    out.failed = true;
    out.error = err.what();
  }
  return out;
}

jobject JNICALL invoke0(JNIEnv* e, jclass, jlong id, jstring jdesc, jobjectArray args, jboolean isVoid) {
  const std::string desc = javaToUtf8(e, jdesc);
  std::shared_ptr<jsi::Object> dispatcher;
  bool isAsync;
  {
    std::lock_guard<std::mutex> lock(gCallbackMutex);
    auto it = gCallbacks.find(id);
    if (it == gCallbacks.end()) {
      e->ThrowNew(gBoot.illegalState, "native-api-bindgen: callback was released");
      return nullptr;
    }
    dispatcher = it->second.dispatcher;
    isAsync = it->second.async.count(desc) > 0;
  }
  Outcome out;
  if (std::this_thread::get_id() == gJsThread && gRuntime != nullptr) {
    out = dispatch(*gRuntime, dispatcher, desc, args);
  } else if (isVoid == JNI_TRUE && isAsync) {
    auto gArgs = args == nullptr ? nullptr : static_cast<jobjectArray>(e->NewGlobalRef(args));
    gInvoker->invokeAsync([dispatcher, desc, gArgs](jsi::Runtime& rt) mutable {
      dispatch(rt, dispatcher, desc, gArgs);
      if (gArgs != nullptr) env()->DeleteGlobalRef(gArgs);
      dispatcher.reset();
    });
    dispatcher.reset();
    return nullptr;
  } else {
    // Blocking: this Java thread waits for the JS thread. Deadlocks if the JS
    // thread is itself blocked waiting on this thread (documented).
    auto gArgs = args == nullptr ? nullptr : static_cast<jobjectArray>(e->NewGlobalRef(args));
    auto promise = std::make_shared<std::promise<Outcome>>();
    auto future = promise->get_future();
    gInvoker->invokeAsync([dispatcher, desc, gArgs, promise](jsi::Runtime& rt) mutable {
      promise->set_value(dispatch(rt, dispatcher, desc, gArgs));
      dispatcher.reset();
    });
    dispatcher.reset();
    out = future.get();
    if (gArgs != nullptr) e->DeleteGlobalRef(gArgs);
  }
  if (out.failed) {
    if (out.result != nullptr) e->DeleteGlobalRef(out.result);
    e->ThrowNew(gBoot.runtimeException, ("Error in JavaScript callback " + desc + ": " + out.error).c_str());
    return nullptr;
  }
  if (out.result == nullptr) return nullptr;
  jobject local = e->NewLocalRef(out.result);
  e->DeleteGlobalRef(out.result);
  return local;
}

void JNICALL release0(JNIEnv*, jclass, jlong id) {
  // Called from the Java finalizer thread: JS objects must die on the JS thread.
  std::shared_ptr<jsi::Object> dispatcher;
  {
    std::lock_guard<std::mutex> lock(gCallbackMutex);
    auto it = gCallbacks.find(id);
    if (it == gCallbacks.end()) return;
    dispatcher = std::move(it->second.dispatcher);
    gCallbacks.erase(it);
  }
  if (gInvoker) {
    gInvoker->invokeAsync([d = std::move(dispatcher)](jsi::Runtime&) mutable { d.reset(); });
  }
}

jsi::Value implement(jsi::Runtime& rt, const jsi::Value* args, std::size_t count) {
  if (count < 2 || !args[0].isString() || !args[1].isObject()) {
    typeError(rt, "implement(interfaceInternalName, dispatcher, asyncDescriptors)");
  }
  if (gHandlerClass == nullptr) {
    throw jsi::JSError(rt, "E010 RUNTIME_BINDING_FAILURE: NabInvocationHandler not found (call nab::initialize from JNI_OnLoad)");
  }
  JNIEnv* e = env();
  LocalFrame frame(e);
  const std::string iface = args[0].getString(rt).utf8(rt);
  jclass ic = e->FindClass(iface.c_str());
  check(rt, e);
  Callback cb;
  cb.dispatcher = std::make_shared<jsi::Object>(args[1].getObject(rt));
  if (count > 2 && args[2].isObject() && args[2].getObject(rt).isArray(rt)) {
    auto arr = args[2].getObject(rt).getArray(rt);
    for (std::size_t i = 0; i < arr.size(rt); i++) {
      cb.async.insert(arr.getValueAtIndex(rt, i).getString(rt).utf8(rt));
    }
  }
  const jlong id = gNextCallback++;
  {
    std::lock_guard<std::mutex> lock(gCallbackMutex);
    gCallbacks.emplace(id, std::move(cb));
  }
  jobject proxy = e->CallStaticObjectMethod(gHandlerClass, gHandlerCreate, id, ic);
  check(rt, e);
  return wrapObject(rt, e, proxy);
}

// ------------------------------------------------------------- root object

class Root : public jsi::HostObject {
 public:
  explicit Root(ClassLookup lookup) : lookup_(lookup) {}

  jsi::Value get(jsi::Runtime& rt, const jsi::PropNameID& name) override {
    const std::string n = name.utf8(rt);
    auto cached = cache_.find(n);
    if (cached != cache_.end()) return jsi::Value(rt, *cached->second);
    jsi::Value v = builtin(rt, n);
    if (v.isUndefined()) {
      const ClassSpec* c = lookup_(n);
      if (c == nullptr) return jsi::Value::undefined();
      v = jsi::Value(rt, makeClassObject(rt, c));
    }
    cache_.emplace(n, std::make_shared<jsi::Value>(rt, v));
    return v;
  }

 private:
  static jsi::Function fn(jsi::Runtime& rt, const char* name, jsi::HostFunctionType f) {
    return jsi::Function::createFromHostFunction(rt, jsi::PropNameID::forAscii(rt, name), 1, std::move(f));
  }

  jsi::Value builtin(jsi::Runtime& rt, const std::string& n) {
    using V = jsi::Value;
    if (n == "version") return jsi::String::createFromAscii(rt, "0.1.0-dev.1");
    if (n == "release") {
      return fn(rt, "release", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        auto h = c > 0 ? handleOf(rt, a[0]) : nullptr;
        if (!h) typeError(rt, "release(handle)");
        if (h->released()) throw jsi::JSError(rt, "DoubleReleaseError: the native object was already released");
        h->release();
        return V::undefined();
      });
    }
    if (n == "isReleased") {
      return fn(rt, "isReleased", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        auto h = c > 0 ? handleOf(rt, a[0]) : nullptr;
        return V(!h || h->released());
      });
    }
    if (n == "isInstanceOf") {
      return fn(rt, "isInstanceOf", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        auto h = c > 1 ? handleOf(rt, a[0]) : nullptr;
        if (!h || !a[1].isString()) typeError(rt, "isInstanceOf(handle, internalName)");
        JNIEnv* e = env();
        LocalFrame frame(e);
        jclass k = e->FindClass(a[1].getString(rt).utf8(rt).c_str());
        if (k == nullptr) {
          e->ExceptionClear();
          return V(false);
        }
        return V(e->IsInstanceOf(h->ref(rt), k) == JNI_TRUE);
      });
    }
    if (n == "isSameObject") {
      return fn(rt, "isSameObject", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        auto x = c > 1 ? handleOf(rt, a[0]) : nullptr;
        auto y = c > 1 ? handleOf(rt, a[1]) : nullptr;
        if (!x || !y) return V(false);
        return V(env()->IsSameObject(x->ref(rt), y->ref(rt)) == JNI_TRUE);
      });
    }
    if (n == "javaToString" || n == "javaClassName" || n == "javaHashCode" || n == "javaEquals") {
      const std::string which = n;
      return fn(rt, n.c_str(), [which](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        auto h = c > 0 ? handleOf(rt, a[0]) : nullptr;
        if (!h) typeError(rt, which + "(handle)");
        JNIEnv* e = env();
        LocalFrame frame(e);
        jobject o = h->ref(rt);
        if (which == "javaToString") {
          auto s = static_cast<jstring>(e->CallObjectMethod(o, gBoot.objectToString));
          check(rt, e);
          return javaStringToJs(rt, e, s);
        }
        if (which == "javaHashCode") {
          auto x = e->CallIntMethod(o, gBoot.objectHashCode);
          check(rt, e);
          return V(static_cast<double>(x));
        }
        if (which == "javaEquals") {
          auto other = c > 1 ? handleOf(rt, a[1]) : nullptr;
          jmethodID eq = e->GetMethodID(gBoot.object, "equals", "(Ljava/lang/Object;)Z");
          auto r = e->CallBooleanMethod(o, eq, other ? other->ref(rt) : nullptr);
          check(rt, e);
          return V(r == JNI_TRUE);
        }
        auto cls = e->CallObjectMethod(o, gBoot.objectGetClass);
        auto s = static_cast<jstring>(e->CallObjectMethod(cls, gBoot.classGetName));
        check(rt, e);
        return javaStringToJs(rt, e, s);
      });
    }
    if (n == "androidSdkInt" || n == "androidSdkIntFull") {
      const bool full = n == "androidSdkIntFull";
      return fn(rt, n.c_str(), [full](jsi::Runtime& rt, const V&, const V*, std::size_t) -> V {
        JNIEnv* e = env();
        LocalFrame frame(e);
        jclass v = e->FindClass("android/os/Build$VERSION");
        check(rt, e);
        const jint sdk = e->GetStaticIntField(v, e->GetStaticFieldID(v, "SDK_INT", "I"));
        if (!full) return V(static_cast<double>(sdk));
        if (sdk < 36) return V(static_cast<double>(sdk) * 100000.0);
        jfieldID f = e->GetStaticFieldID(v, "SDK_INT_FULL", "I");
        if (f == nullptr) {
          e->ExceptionClear();
          return V(static_cast<double>(sdk) * 100000.0);
        }
        return V(static_cast<double>(e->GetStaticIntField(v, f)));
      });
    }
    if (n == "registerView" || n == "unregisterView") {
      const bool reg = n == "registerView";
      return fn(rt, n.c_str(), [reg](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        if (gViewsClass == nullptr) {
          throw jsi::JSError(rt, "E010 RUNTIME_BINDING_FAILURE: NabViews not found");
        }
        JNIEnv* e = env();
        LocalFrame frame(e);
        if (reg) {
          auto h = c > 0 ? handleOf(rt, a[0]) : nullptr;
          if (!h) typeError(rt, "registerView(handle)");
          const jlong id = e->CallStaticLongMethod(gViewsClass, gViewsRegister, h->ref(rt));
          check(rt, e);
          return V(static_cast<double>(id));
        }
        if (c == 0 || !a[0].isNumber()) typeError(rt, "unregisterView(id)");
        e->CallStaticVoidMethod(gViewsClass, gViewsUnregister, static_cast<jlong>(a[0].getNumber()));
        check(rt, e);
        return V::undefined();
      });
    }
    if (n == "implement") {
      return fn(rt, "implement", [](jsi::Runtime& rt, const V&, const V* a, std::size_t c) -> V {
        return implement(rt, a, c);
      });
    }
    if (n == "applicationContext" || n == "currentActivity") {
      const bool app = n == "applicationContext";
      return fn(rt, n.c_str(), [app](jsi::Runtime& rt, const V&, const V*, std::size_t) -> V {
        if (gContextClass == nullptr) {
          throw jsi::JSError(rt, "E010 RUNTIME_BINDING_FAILURE: NabContext not found");
        }
        JNIEnv* e = env();
        LocalFrame frame(e);
        jobject o = e->CallStaticObjectMethod(gContextClass, app ? gAppContext : gCurrentActivity);
        check(rt, e);
        return wrapObject(rt, e, o);
      });
    }
    return V::undefined();
  }

  ClassLookup lookup_;
  std::unordered_map<std::string, std::shared_ptr<jsi::Value>> cache_;
};

} // namespace

void initialize(JavaVM* vm) {
  gVm = vm;
  JNIEnv* e = env();
  initBoot(e);
  gHandlerClass = globalClass(e, "dev/nativeapibindgen/runtime/NabInvocationHandler");
  if (gHandlerClass != nullptr) {
    gHandlerCreate = e->GetStaticMethodID(gHandlerClass, "create", "(JLjava/lang/Class;)Ljava/lang/Object;");
    static const JNINativeMethod natives[] = {
        {const_cast<char*>("invoke0"),
         const_cast<char*>("(JLjava/lang/String;[Ljava/lang/Object;Z)Ljava/lang/Object;"),
         reinterpret_cast<void*>(&invoke0)},
        {const_cast<char*>("release0"), const_cast<char*>("(J)V"), reinterpret_cast<void*>(&release0)},
    };
    e->RegisterNatives(gHandlerClass, natives, 2);
  }
  gContinuationClass = globalClass(e, "dev/nativeapibindgen/runtime/NabContinuation");
  if (gContinuationClass != nullptr) {
    gContinuationCreate = e->GetStaticMethodID(gContinuationClass, "create", "(J)Ljava/lang/Object;");
    gContinuationIsSuspended = e->GetStaticMethodID(gContinuationClass, "isSuspended", "(Ljava/lang/Object;)Z");
    static const JNINativeMethod suspendNatives[] = {
        {const_cast<char*>("resume0"), const_cast<char*>("(JLjava/lang/Object;)V"), reinterpret_cast<void*>(&resume0)},
        {const_cast<char*>("fail0"), const_cast<char*>("(JLjava/lang/Throwable;)V"), reinterpret_cast<void*>(&fail0)},
    };
    e->RegisterNatives(gContinuationClass, suspendNatives, 2);
  }
  gViewsClass = globalClass(e, "dev/nativeapibindgen/runtime/NabViews");
  if (gViewsClass != nullptr) {
    gViewsRegister = e->GetStaticMethodID(gViewsClass, "register", "(Ljava/lang/Object;)J");
    gViewsUnregister = e->GetStaticMethodID(gViewsClass, "unregister", "(J)V");
  }
  gContextClass = globalClass(e, "dev/nativeapibindgen/runtime/NabContext");
  if (gContextClass != nullptr) {
    gAppContext = e->GetStaticMethodID(gContextClass, "applicationContext", "()Landroid/content/Context;");
    gCurrentActivity = e->GetStaticMethodID(gContextClass, "currentActivity", "()Landroid/app/Activity;");
  }
  e->ExceptionClear();
}

void install(
    jsi::Runtime& rt,
    std::shared_ptr<facebook::react::CallInvoker> invoker,
    ClassLookup lookup,
    bool longAsBigInt) {
  gJsThread = std::this_thread::get_id();
  gRuntime = &rt;
  gInvoker = std::move(invoker);
  gLongAsBigInt = longAsBigInt;
  rt.global().setProperty(rt, "__nab", jsi::Object::createFromHostObject(rt, std::make_shared<Root>(lookup)));
}

} // namespace nab
