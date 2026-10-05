# PROJECT: Universal Native API Bindgen for Flutter + React Native

## ROLE

You are acting as a principal-level compiler engineer, native platform engineer, SDK/toolchain engineer, Flutter/Dart interoperability engineer, React Native New Architecture engineer, API/code-generation architect, test engineer, open-source maintainer, documentation engineer, SEO engineer, and security/privacy engineer.

Your job is to design and implement this project as a serious public open-source developer tool.

Do not build a demo, toy wrapper, manually maintained plugin, or proof-of-concept that only supports a few APIs.

Build the architecture so that it can eventually generate a broad typed mirror of supported public Android and Apple platform SDK APIs automatically.

Do not blindly follow assumptions from this prompt where official documentation contradicts them. Verify technical behavior against current first-party documentation and installed SDK/toolchain behavior.

---

# 1. CORE PRODUCT VISION

Create a project called:

`native-api-bindgen`

Use this name throughout the initial implementation, but keep package names/configuration centralized so it can be renamed later.

The product goal is:

> Automatically generate strongly typed native API bindings for supported public Android and Apple platform SDK APIs so Flutter/Dart and React Native/TypeScript developers can directly use native APIs without manually writing repetitive MethodChannel, NativeModule, JNI wrapper, Objective-C wrapper, or similar glue code.

The project must NOT claim to expose literally every private/internal operating-system symbol.

The official product terminology must instead be:

> "Automatically generated bindings for supported public platform SDK APIs."

The project must clearly distinguish:

1. Public supported API
2. Deprecated API
3. API unavailable on target OS version
4. Hidden/non-SDK Android API
5. Private Apple API
6. Unsupported language construct
7. Unsupported ABI/type mapping
8. Documentation unavailable
9. License/reuse restricted source material

---

# 2. NON-NEGOTIABLE ARCHITECTURAL PRINCIPLE

Do NOT generate Dart or TypeScript directly from documentation pages.

Documentation pages are enrichment/input metadata only.

The canonical pipeline must be:

```text
Platform SDK / SDK Metadata / Compiler AST / API Metadata
                     +
         Official documentation metadata
                     +
             Official annotations
                     ↓
              Platform Parser
                     ↓
             Canonical Native IR
                     ↓
        Validation / Normalization
                     ↓
         ┌───────────┴───────────┐
         │                       │
     Flutter target          React Native target
         │                       │
    Dart generators         TS/C++ generators
         │                       │
   JNI / FFI / ObjC          JSI / JNI / ObjC++
         │                       │
              Native platform
```

The Native IR is the central source of truth.

Do not create separate incompatible parser models for every output language.

---

# 3. OFFICIAL-SOURCE POLICY

Use first-party sources only for platform API facts.

Allowed source domains:

Android:

* developer.android.com
* source.android.com
* android.googlesource.com where appropriate for official Android source
* official Android SDK metadata installed locally

Flutter/Dart:

* dart.dev
* api.dart.dev
* pub.dev only for official Dart packages when the package itself is the subject
* docs.flutter.dev
* flutter.dev

React Native:

* reactnative.dev
* official React Native GitHub repository only when necessary for implementation/source verification

Apple:

* developer.apple.com
* Xcode SDK headers/framework metadata installed locally
* Swift compiler/toolchain installed locally
* official Apple SDK/toolchain facilities

GitHub:

* docs.github.com

Do NOT use:

* Stack Overflow as an authoritative implementation source
* blogs as authoritative API metadata
* random GitHub generators as the source of truth
* unofficial API mirrors as authoritative metadata
* scraped third-party API documentation
* reverse-engineered private APIs as supported public APIs

Third-party sources may only be used to understand an implementation idea. They must NEVER become the source of truth for public generated API metadata.

Every generated symbol must be traceable to a first-party source.

---

# 4. CURRENT OFFICIAL TECHNOLOGY BASELINE

Before implementing each subsystem, consult the current official documentation.

For Flutter/Dart:

Use the currently recommended native interop architecture rather than obsolete plugin patterns.

Relevant official technologies include:

* `dart:ffi`
* FFIgen
* `package:jnigen`
* JNI runtime
* Objective-C interop
* `package:objective_c`
* Flutter native assets/build hooks where applicable

Flutter's currently recommended FFI package approach uses build hooks for native assets.

Do not introduce the legacy `plugin_ffi` model unless a concrete requirement requires it.

For Android:

* Java/Kotlin SDK APIs
* Android SDK platform metadata
* Android annotations
* JNI
* installed SDK/platform information
* official API-level information

For iOS:

* Objective-C headers
* Clang AST information
* Xcode SDK metadata
* Swift compiler/toolchain
* Objective-C interoperability
* FFIgen-compatible representations
* Swift → Objective-C exposure where appropriate

For React Native:

* New Architecture
* JSI
* TurboModules where the architecture requires them
* Codegen where useful/required
* generated C++ bindings
* Java/Kotlin Android integration
* Objective-C++ / Objective-C iOS integration

Do not build around the legacy React Native bridge unless legacy compatibility is explicitly required as an optional compatibility layer.

---

# 5. WHAT THE PRODUCT MUST PROVIDE

The system must support this workflow:

```bash
native-api-bindgen init
```

```bash
native-api-bindgen detect
```

```bash
native-api-bindgen inspect android
```

```bash
native-api-bindgen inspect ios
```

```bash
native-api-bindgen generate android
```

```bash
native-api-bindgen generate ios
```

```bash
native-api-bindgen generate flutter
```

```bash
native-api-bindgen generate react-native
```

```bash
native-api-bindgen generate all
```

```bash
native-api-bindgen update
```

```bash
native-api-bindgen diff android
```

```bash
native-api-bindgen diff ios
```

```bash
native-api-bindgen coverage
```

```bash
native-api-bindgen doctor
```

```bash
native-api-bindgen audit-license
```

```bash
native-api-bindgen clean
```

Eventually support:

```bash
native-api-bindgen update --all
```

which detects installed platform SDK/toolchain versions and regenerates supported bindings.

---

# 6. HIGH-LEVEL MONOREPO STRUCTURE

Create a monorepo approximately like:

```text
native-api-bindgen/
│
├── README.md
├── LICENSE
├── NOTICE
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── SUPPORT.md
├── GOVERNANCE.md
├── CHANGELOG.md
│
├── docs/
│   ├── architecture/
│   ├── getting-started/
│   ├── android/
│   ├── ios/
│   ├── flutter/
│   ├── react-native/
│   ├── compatibility/
│   ├── legal/
│   └── troubleshooting/
│
├── packages/
│   │
│   ├── native_api_ir/
│   │
│   ├── native_api_core/
│   │
│   ├── native_api_generator/
│   │
│   ├── native_api_cli/
│   │
│   ├── native_api_android/
│   │
│   ├── native_api_ios/
│   │
│   ├── native_api_flutter_android/
│   │
│   ├── native_api_flutter_ios/
│   │
│   ├── native_api_react_native_android/
│   │
│   └── native_api_react_native_ios/
│
├── generators/
│   ├── android/
│   ├── apple/
│   ├── flutter/
│   └── react-native/
│
├── runtimes/
│   ├── dart/
│   ├── jni/
│   ├── objective-c/
│   ├── jsi/
│   └── cpp/
│
├── fixtures/
│   ├── android/
│   ├── ios/
│   ├── kotlin/
│   ├── java/
│   ├── swift/
│   └── objective-c/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── golden/
│   ├── compatibility/
│   ├── generation/
│   ├── runtime/
│   ├── performance/
│   └── legal/
│
├── examples/
│   ├── flutter/
│   ├── react-native/
│   ├── android/
│   └── ios/
│
├── website/
│   ├── index.html
│   ├── docs.html
│   ├── architecture.html
│   ├── compatibility.html
│   ├── legal.html
│   ├── examples.html
│   ├── faq.html
│   ├── robots.txt
│   ├── sitemap.xml
│   ├── site.webmanifest
│   ├── assets/
│   └── README.md
│
└── .github/
    ├── workflows/
    ├── ISSUE_TEMPLATE/
    ├── pull_request_template.md
    └── dependabot.yml
```

Adapt the exact structure to the chosen implementation language/tooling, but maintain the architectural separation.

---

# 7. NATIVE IR

Design a canonical Intermediate Representation.

The IR must be serializable to JSON for diagnostics and debugging.

Example:

```json
{
  "platform": "android",
  "platformVersion": "36",
  "namespace": "android.content",
  "name": "Intent",
  "kind": "class",
  "availability": {
    "introducedApi": 1,
    "deprecatedApi": null,
    "removedApi": null
  },
  "annotations": [],
  "documentation": {
    "summary": "...",
    "sourceType": "official",
    "sourceReference": "..."
  },
  "constructors": [],
  "methods": [],
  "fields": [],
  "properties": [],
  "interfaces": [],
  "superClass": "android.content.Object"
}
```

Do not copy this exact simplistic schema if a more robust model is required.

The real IR must model:

* namespaces/modules
* classes
* structs
* enums
* interfaces/protocols
* protocols
* constructors
* destructors where relevant
* functions
* methods
* static methods
* instance methods
* properties
* fields
* constants
* associated types where relevant
* generic type parameters
* generic bounds
* nullable types
* arrays
* maps
* lists
* sets
* pointers
* function types
* callbacks
* closures
* delegates
* listeners
* annotations
* attributes
* availability
* deprecation
* platform
* SDK version
* threading requirements
* actor requirements
* permissions
* exception semantics
* error semantics
* ownership
* reference semantics
* async semantics
* documentation
* source location
* source provenance
* licensing metadata
* support status
* generator diagnostics

Every IR node must have stable identity.

Example:

```text
android.content.Intent#setData(Uri)
```

must have a deterministic symbol ID independent of generated file naming.

---

# 8. SOURCE PROVENANCE

Every generated symbol must include provenance metadata.

For example:

```json
{
  "symbolId": "android.content.Intent#setData(android.net.Uri)",
  "source": {
    "platform": "android",
    "sourceKind": "sdk",
    "sdkVersion": "36",
    "officialReference": "...",
    "localArtifact": "android.jar"
  }
}
```

For Apple:

Do not store or publish copyrighted Apple SDK source code.

Store metadata such as:

* framework
* symbol name
* SDK version
* header name/path where locally available
* source kind
* availability
* generated status
* legal classification

Do not embed Apple SDK files into the repository.

---

# 9. ANDROID DISCOVERY

Implement Android SDK discovery.

Search standard SDK locations plus documented environment variables.

Support:

```text
ANDROID_HOME
ANDROID_SDK_ROOT
```

Detect:

* installed platform versions
* build-tools
* platform jars
* source packages where available
* SDK manager availability
* JDK version
* Gradle compatibility where relevant
* NDK availability when needed

Use officially documented Android SDK mechanisms.

Do not download Android SDK components silently without user consent.

Provide:

```bash
native-api-bindgen doctor
```

that reports:

```text
Android SDK: detected
Platform API: 36
Build tools: detected
JDK: detected
JNI generator: detected
License status: ...
```

---

# 10. ANDROID API EXTRACTION

For Android Java/Kotlin APIs:

Use official SDK artifacts and supported compiler/reflection/metadata mechanisms.

Primary API signature source should be machine-readable SDK artifacts, not HTML.

Extract:

* package
* class
* interface
* enum
* annotation
* constructor
* method
* overload
* parameter
* generic type
* return type
* fields
* constants
* inheritance
* interfaces
* annotations
* nullability where available
* API-level availability
* deprecation
* hidden/non-SDK status where detectable

Use official Android metadata where available.

Generate diagnostics when Android APIs cannot be represented exactly.

Never silently drop an API.

---

# 11. ANDROID ANNOTATION HANDLING

Build a generalized annotation model.

Handle, where available and semantically meaningful:

* nullability
* API availability
* deprecation
* permissions
* threading
* constants/flags
* resource annotations
* type restrictions
* range constraints
* callback semantics

Do not blindly transform every Java annotation into an invented Dart annotation.

Instead classify:

```text
semantic
preservable
runtime
compile-time
documentation-only
unsupported
```

Provide raw annotation metadata for diagnostics.

Example:

```text
AnnotationClassification:
  Semantic
  Metadata
  Runtime
  Unsupported
```

---

# 12. ANDROID NON-SDK / HIDDEN API POLICY

Do not expose private Android implementation details as supported public APIs.

If hidden/non-SDK APIs are detected:

```text
status = hidden_or_non_sdk
support = unsupported
```

They may appear in diagnostics but must not be represented as normal public API output.

Do not encourage bypassing Android's non-SDK restrictions.

---

# 13. JAVA/KOTLIN TYPE SYSTEM

Support as much of the Java/Kotlin type system as reasonably possible.

At minimum model:

* primitives
* boxed primitives
* String
* arrays
* objects
* interfaces
* enums
* generics
* wildcard types
* nullable references
* generic bounds
* nested classes
* anonymous/callback interfaces where representable
* static members
* overloaded methods
* varargs

Investigate Kotlin bytecode/signature information.

Do not assume Java source and Kotlin source are identical.

Where Kotlin-specific constructs cannot be represented exactly, document the limitation.

---

# 14. GENERIC TYPE MAPPING

Create a centralized type-mapping engine.

Example conceptual mappings:

```text
Java int              → Dart int
Java long             → Dart int
Java double           → Dart double
Java boolean          → Dart bool
java.lang.String      → Dart String
Nullable reference    → Dart nullable type
Java array            → generated typed wrapper
List<T>               → generated collection abstraction
Map<K,V>               → generated map abstraction
```

Do not hard-code these mappings in individual generators.

Use a shared type system.

Support configurable:

```text
strict-native
ergonomic-dart
strict-typescript
ergonomic-typescript
```

modes where appropriate.

---

# 15. NATIVE OBJECT LIFECYCLE

Create a common native-handle model.

Every wrapped native object must have a clear ownership strategy.

Conceptually:

```text
Dart/RN object
      ↓
Managed native handle
      ↓
Native object
```

Handle:

* strong references
* weak references where appropriate
* finalization
* explicit close/dispose when required
* idempotent disposal
* use-after-dispose protection
* thread safety
* object identity
* object equality semantics
* native reference lifetime

Do not leak JNI or Objective-C objects.

Create stress tests for:

* repeated create/dispose
* garbage collection
* callbacks after disposal
* retained callback objects
* retained native objects
* cyclic references

---

# 16. ANDROID CALLBACKS

Support interfaces/listeners.

For example:

```text
LocationListener
TextWatcher
SensorEventListener
```

The generator should create proxy/adaptor implementations where technically supported.

Conceptually:

```text
Dart callback
   ↓
Generated proxy
   ↓
JNI
   ↓
Java interface
   ↓
Android callback
   ↓
JNI
   ↓
Dart callback
```

Support:

* callback registration
* callback removal
* object retention
* lifecycle cleanup
* exception propagation
* thread dispatch
* callback thread metadata

Write integration tests for every supported callback mechanism.

---

# 17. THREADING

Represent threading metadata in the IR.

Examples:

```text
main-thread
UI-thread
background-thread
unspecified
actor-isolated
dispatch-queue
```

Map Android UI/main-thread constraints appropriately.

Map Apple main-actor/main-thread requirements appropriately.

Do not pretend that every native API is thread-safe.

Expose warnings in generated documentation and diagnostics.

---

# 18. ASYNC SUPPORT

Support native asynchronous APIs where possible.

Android:

* callbacks
* Future-like APIs
* Kotlin suspend functions
* coroutine-related APIs
* Flow/observable concepts where representable

iOS:

* completion handlers
* Swift async functions where exposed/bridgeable
* async sequences where realistically supported

React Native:

* Promise-returning methods
* synchronous methods where safe
* native object references for JSI where appropriate

Do not fake synchronous behavior for APIs that are inherently asynchronous.

---

# 19. ERROR / EXCEPTION TRANSLATION

Create a central error model.

Android may involve:

```text
Throwable
Exception
Error
```

Apple may involve:

```text
NSError
NSException
Swift Error
```

Map to:

```text
Dart Exception/Error/Future error
TypeScript Error/Promise rejection
```

Preserve:

* native class name
* error domain where available
* error code
* message
* stack where safely available
* native diagnostic information

Never swallow exceptions silently.

---

# 20. iOS SDK DISCOVERY

Use the locally installed Xcode toolchain.

Do not vendor Apple SDKs.

Detect:

```bash
xcode-select
xcrun
xcodebuild
```

and SDK paths.

Discover:

* iphoneos SDK
* iphonesimulator SDK
* framework paths
* headers
* Clang
* Swift compiler
* Objective-C metadata
* SDK version

Support simulator and physical-device targets properly.

Do not assume paths are identical across machines.

---

# 21. OBJECTIVE-C PARSING

Use the official local SDK headers and Clang-compatible AST information.

Extract:

* classes
* methods
* properties
* protocols
* categories
* enums
* typedefs
* constants
* blocks
* nullability
* availability
* deprecation
* macros that materially affect API semantics
* Swift naming attributes
* Objective-C runtime metadata where appropriate

Do not scrape Apple documentation to reconstruct API signatures if local SDK headers already provide the authoritative declaration.

---

# 22. SWIFT SUPPORT

Treat Swift support as layered.

### Layer 1

Objective-C-compatible Swift APIs.

Use normal Objective-C interoperability.

### Layer 2

Swift APIs that can have generated Objective-C exposure.

Use controlled adapters.

### Layer 3

Swift-only constructs.

Support incrementally and conservatively.

Do not claim universal Swift support.

For Swift-only APIs, generate an adapter only when a stable and documented implementation path exists.

Potential concepts include:

```text
Swift → Objective-C header → generated interop
```

or:

```text
Swift adapter → C ABI → Dart FFI
```

Use a generated C ABI layer only when necessary.

Do not rely on private compiler internals unless explicitly isolated as experimental.

---

# 23. APPLE AVAILABILITY

Parse and preserve:

* iOS availability
* iPadOS availability where applicable
* macOS availability where relevant
* simulator/device differences
* deprecated
* unavailable
* introduced versions
* obsoleted versions

Generate runtime-safe availability handling.

Do not call an API on unsupported OS versions without appropriate guards.

---

# 24. APPLE LEGAL RESTRICTIONS

This is mandatory.

Do not:

* vendor Apple SDKs
* commit Apple SDK files into Git
* publish Apple framework binaries copied from Xcode
* copy large Apple documentation bodies into generated packages
* scrape and republish Apple's documentation as if it were project content
* bypass Apple's licensing restrictions
* expose private Apple APIs as supported
* encourage App Store policy evasion

The project may generate bindings against SDK/toolchain resources installed on the developer's own machine, subject to applicable Apple terms.

Generated output should primarily contain:

* API declarations
* generated binding code
* metadata
* symbol names
* availability metadata
* developer-authored documentation
* references to official Apple documentation

Use concise paraphrased documentation rather than reproducing large sections of Apple documentation.

Create a `docs/legal/apple.md` explaining this policy.

Add automated repository checks that detect accidentally committed Apple SDK artifacts.

---

# 25. ANDROID LEGAL / ATTRIBUTION POLICY

Review the applicable Android documentation and SDK license terms before redistributing any generated content.

Do not blindly copy entire documentation websites.

For Android documentation:

* preserve required attribution where applicable
* preserve applicable license notices
* separate project-authored content from third-party content
* keep third-party license information in NOTICE/THIRD_PARTY_NOTICES where required
* do not imply Google endorsement

Use the official Android attribution wording when the project references the Android name.

Do not use Google's trademarks/logos to imply endorsement.

---

# 26. THIRD-PARTY LICENSE SYSTEM

Create:

```text
THIRD_PARTY_NOTICES.md
licenses/
```

and a generated dependency/license report.

The generator should track:

```text
source
license
license URL/reference
redistribution allowed?
required attribution?
generated artifact?
documentation copied?
```

Add:

```bash
native-api-bindgen audit-license
```

The command must produce:

```text
PASS
WARN
BLOCK
```

statuses.

Publishing must fail when a known restricted artifact is detected.

Do not invent licensing permissions.

When licensing cannot be confidently classified, mark:

```text
REVIEW_REQUIRED
```

instead of assuming permission.

This is an engineering compliance mechanism, not a substitute for legal counsel.

---

# 27. PROJECT LICENSE

Choose a permissive OSI-approved license for the project's own original source unless the repository owner explicitly selects another.

A strong default candidate is Apache-2.0 because of its explicit patent grant, but document that license selection is a project/legal decision.

Do not apply the project license to:

* Apple SDK files
* Android SDK files that carry separate applicable licensing
* third-party generated content
* external documentation
* vendored components with incompatible licenses

Clearly mark ownership boundaries.

---

# 28. FLUTTER RUNTIME

Build the Flutter side around supported Dart native interop mechanisms.

Android:

```text
Dart
 ↓
Generated Dart binding
 ↓
JNI runtime
 ↓
Java/Kotlin API
```

iOS:

```text
Dart
 ↓
Generated Dart binding
 ↓
dart:ffi / Objective-C interop
 ↓
Objective-C / Swift adapter
 ↓
Apple SDK
```

Avoid MethodChannel for the generated native API surface.

A manually written MethodChannel must not become the hidden transport layer for the generated APIs.

Only use Flutter Plugin APIs where a specific platform integration genuinely requires them and document why.

---

# 29. FLUTTER API DESIGN

The generated APIs should look natural but remain traceable to native APIs.

Example:

```dart
final intent = Intent(action: Intent.ACTION_VIEW);
intent.setData(uri);
activity.startActivity(intent);
```

Also provide a strict mode where native semantics remain visible.

Generate API documentation such as:

```dart
/// Native API: android.content.Intent#setData
///
/// Android API: 1
///
/// Availability: Android 1+
```

Do not write a hand-made wrapper for every native API.

Use templates/generators.

---

# 30. REACT NATIVE RUNTIME

Use React Native New Architecture mechanisms.

Primary architecture:

```text
TypeScript
 ↓
JSI / generated interface
 ↓
C++
 ↓
Android JNI / Java-Kotlin
or
iOS Objective-C++ / Swift
```

Use TurboModules/Codegen where required by the React Native platform integration model.

Do not build a giant serialized JSON bridge.

Do not make the legacy React Native bridge the core architecture.

---

# 31. REACT NATIVE API GENERATION

Generate:

* TypeScript declarations
* typed native specifications where Codegen expects them
* C++ glue
* Android implementation
* iOS implementation
* platform-specific object adapters

Preserve:

* native methods
* native classes represented as object handles
* sync/async semantics
* callbacks/events
* typed values
* errors

Where the native API is object-oriented, do not flatten everything into one huge function namespace unless technically necessary.

---

# 32. REACT NATIVE OBJECT REFERENCES

For APIs such as:

```text
Camera
AVAudioEngine
Bitmap
Surface
UIView
Activity
Context
```

support native object references.

Conceptual model:

```text
JS object
 ↓
JSI HostObject
 ↓
C++ wrapper
 ↓
native object
```

Implement safe lifetime rules.

Test:

* JS garbage collection
* native references
* explicit disposal
* callbacks after disposal
* JS object identity
* thread safety
* cross-thread misuse

---

# 33. APP SIZE / DEAD CODE ELIMINATION

The generated API universe may be extremely large.

Do not package every generated native implementation into every application unnecessarily.

Architecture must be linker/shrinker friendly.

Avoid global reflection registries.

Avoid "register every class at startup."

Prefer direct generated symbol references.

Support modular/sharded generation.

Example:

```text
native_android_core
native_android_app
native_android_camera
native_android_location
native_android_media
native_android_network
native_android_sensor
...
```

Likewise for Apple.

The public API may provide an umbrella import while internal generated modules remain independently linkable.

Generate direct references so unused symbols can be removed by:

* Dart tree shaking
* Android R8
* native linker dead-code elimination
* iOS linker optimization
* C++ dead stripping

Do not claim "zero size increase."

Instead measure and document actual overhead.

---

# 34. BINARY-SIZE TESTS

Create sample apps:

1. baseline Flutter app
2. generated package imported but unused
3. generated package using one simple API
4. generated package using a complex API
5. multiple generated APIs

Measure:

* Android APK
* Android AAB
* native `.so`
* iOS app size
* IPA/archive size where reproducible
* startup impact
* memory impact

Publish benchmark methodology.

Acceptance criterion:

The generated library must not statically force the complete API universe into the final application.

---

# 35. PERFORMANCE TESTS

Measure:

* JNI call overhead
* FFI call overhead
* Objective-C interop overhead
* JSI call overhead
* native object creation
* callback latency
* high-frequency callback throughput
* large byte-buffer transfer
* object retention
* application startup cost

Compare against:

* direct native implementation
* MethodChannel where an equivalent exists
* generated JSI/FFI path

Do not claim "faster" until benchmarked.

---

# 36. ZERO-COPY DATA PATHS

Where technically possible, support efficient native data exchange.

Investigate:

* typed byte buffers
* memory views
* direct buffers
* native pointers/handles
* JSI ArrayBuffer-like mechanisms
* FFI memory
* image/audio/frame buffers

Do not expose unsafe memory APIs by default.

Clearly mark unsafe operations.

---

# 37. NATIVE UI

Native UI must be treated separately from simple object APIs.

Examples:

Android:

* View
* ViewGroup
* SurfaceView
* TextureView
* RecyclerView
* WebView

Apple:

* UIView
* UIViewController
* CALayer
* WKWebView

Native UI requires:

* main-thread behavior
* lifecycle
* ownership
* parent-child hierarchy
* rendering
* event callbacks
* platform lifecycle

Do not promise that native UI can always be represented as ordinary Dart/TypeScript objects.

Create a separate:

```text
Native UI integration layer
```

and mark unsupported UI classes clearly.

---

# 38. GENERATED DOCUMENTATION

Generate documentation for every supported symbol.

Each generated API page should include:

* native symbol
* generated symbol
* platform
* SDK version
* availability
* deprecated status
* annotations
* parameter types
* return type
* threading requirements
* permissions
* provenance
* official source reference
* generated compatibility information

Do not copy large copyrighted documentation sections.

Prefer concise generated summaries and links/references to official documentation.

---

# 39. VERSIONING MODEL

Use two version dimensions.

Project version:

```text
native-api-bindgen 0.x.y
```

Platform SDK version:

```text
Android API 36
iOS SDK 26.x
```

Track:

```text
generatorVersion
runtimeVersion
sdkVersion
apiLevel
sourceRevision
```

Generated artifacts must embed this metadata.

---

# 40. API DIFF TOOL

Implement:

```bash
native-api-bindgen diff android --from <version> --to <version>
```

and:

```bash
native-api-bindgen diff ios --from <version> --to <version>
```

Output:

```text
Added
Removed
Deprecated
Changed
Availability changed
Annotation changed
Signature changed
Documentation metadata changed
Unsupported newly detected
```

Example:

```text
ADDED
android.foo.Bar.newMethod()

DEPRECATED
android.foo.Bar.oldMethod()

CHANGED
android.foo.Bar.getValue()
return type: int → long
```

Never infer semantic changes only from documentation prose if machine-readable signatures are available.

---

# 41. UPDATE WORKFLOW

A normal developer should be able to run:

```bash
native-api-bindgen update
```

and receive:

1. detected SDK versions
2. source changes
3. IR regeneration
4. generator execution
5. tests
6. API compatibility report
7. license audit
8. generated documentation update
9. generation summary

Example:

```text
Detected Android API 36
Detected iOS SDK 26.x

Generating Android...
Generating iOS...

Generated:
  classes: ...
  methods: ...
  callbacks: ...
  annotations: ...

Skipped:
  unsupported Swift features: ...
  private APIs: ...

License audit: PASS
Tests: PASS
```

---

# 42. DETERMINISTIC GENERATION

The generator must be deterministic.

The same:

```text
SDK
generator version
configuration
```

must produce the same output.

Normalize:

* ordering
* whitespace
* generated identifiers
* JSON ordering
* timestamps
* generated comments

Do not insert current timestamps into generated source unless explicitly requested.

Provide:

```bash
native-api-bindgen verify-reproducible
```

that generates twice and compares results.

---

# 43. GOLDEN TESTS

Use golden/snapshot tests for generated APIs.

Fixture:

```text
fixtures/android/basic/
fixtures/apple/basic/
```

Expected:

```text
golden/flutter/
golden/react-native/
golden/native/
```

Test representative:

* classes
* overloads
* generics
* nullable types
* annotations
* enums
* callbacks
* exceptions
* availability
* deprecated methods
* nested classes
* protocols
* properties
* async APIs

Golden tests must be stable across machines.

---

# 44. UNIT TESTS

Create unit tests for:

## Parser

* Java parsing
* Kotlin metadata parsing
* Objective-C AST parsing
* availability parsing
* annotation parsing
* generics
* overloads
* constants
* inheritance

## IR

* symbol identity
* normalization
* type mapping
* metadata validation
* serialization
* deserialization

## Generators

* Dart
* TypeScript
* C++
* JNI
* Objective-C
* Swift adapters

## Runtime

* lifecycle
* callbacks
* errors
* threading
* ownership

---

# 45. INTEGRATION TESTS

Create actual:

### Flutter Android app

Test:

```text
Intent
Uri
Bundle
Context
Activity
Handler
Looper
```

and representative callbacks.

### Flutter iOS app

Test:

```text
NSString
NSArray
NSDictionary
NSObject
UIView
Foundation APIs
UIKit APIs
```

plus availability handling.

### React Native Android app

Test:

* JSI object
* native method
* callback
* async method
* error
* lifecycle

### React Native iOS app

Test equivalent functionality.

Do not rely only on mocked tests.

At least a small set of end-to-end tests must execute against real platform SDKs.

---

# 46. COMPATIBILITY MATRIX

Create a compatibility matrix for:

```text
Flutter versions
Dart versions
Android SDK versions
minimum Android API
Xcode versions
iOS SDK versions
React Native versions
Node versions
JDK versions
```

Do not hard-code future versions.

Use a CI matrix for officially tested versions.

When the current official documentation changes, update the matrix based on actual supported versions.

---

# 47. CI

Use GitHub Actions.

Workflows:

```text
ci.yml
android.yml
ios.yml
flutter.yml
react-native.yml
generator.yml
license-audit.yml
security.yml
website.yml
release.yml
```

CI must run:

* formatting
* linting
* unit tests
* golden tests
* generation tests
* license audit
* dependency audit
* deterministic generation
* documentation build
* website build
* link validation
* package validation

Platform-specific runners should be used only where needed.

Do not make every job unnecessarily dependent on macOS.

---

# 48. SECURITY

Treat generated native bindings as security-sensitive infrastructure.

Implement:

* no arbitrary remote code execution from API metadata
* no shell command execution from untrusted generated content
* no unsafe path traversal
* no generated code writing outside output directories
* path validation
* input validation
* bounded parser memory usage
* recursion limits where appropriate
* malicious fixture tests
* reproducible generation
* checksum verification for any optional downloaded third-party artifact

Never download and execute a binary merely because a configuration file references it.

---

# 49. NETWORK POLICY

Generation should work offline whenever the necessary SDK/toolchain is installed.

Do not require scraping the Internet for every build.

Preferred order:

```text
1. Local SDK metadata
2. Local compiler/headers
3. Local official source packages
4. Official documentation/API metadata when needed
5. Network access only when explicitly requested/configured
```

Do not silently send source code, API metadata, identifiers, or project data to a remote service.

The initial project must not require a backend.

---

# 50. DOCUMENTATION FOR LEGAL SOURCE PROVENANCE

Create:

```text
docs/legal/source-provenance.md
docs/legal/android.md
docs/legal/apple.md
docs/legal/flutter.md
docs/legal/react-native.md
```

Explain:

* what information is generated
* from where
* what is locally consumed
* what is redistributed
* what is not redistributed
* attribution requirements
* third-party dependencies
* private API policy

Do not present these documents as legal advice.

Clearly state that organizations should perform their own legal review before commercial redistribution where necessary.

---

# 51. PACKAGE PUBLISHING

Prepare public packages for appropriate registries.

Flutter packages:

* valid `pubspec.yaml`
* package metadata
* README
* CHANGELOG
* LICENSE
* example
* tests
* platform support declarations

React Native:

* `package.json`
* npm package metadata
* TypeScript declarations
* React Native configuration
* Android/iOS native source
* README
* CHANGELOG
* LICENSE

Do not publish SDK artifacts that cannot legally be redistributed.

If a generated API requires a local SDK, publish the generator and metadata rules rather than copying the restricted SDK content.

---

# 52. GENERATED-ARTIFACT POLICY

Clearly distinguish:

```text
source repository
generated local output
published runtime
published generated bindings
local SDK inputs
third-party SDK files
```

Some generated bindings may be publishable.

Some may need to remain locally generated.

Create configuration:

```yaml
distribution:
  generatedArtifacts: allowed | local-only
  documentationMode: summary | links-only
```

Default to the safest legal behavior.

---

# 53. API COVERAGE REPORT

Implement:

```bash
native-api-bindgen coverage
```

Example output:

```text
Android SDK API 36

Classes discovered: 31,482
Classes generated: 30,910
Methods discovered: 428,921
Methods generated: 412,305

Coverage:
  classes       98.2%
  methods       96.1%
  callbacks     94.7%
  annotations   92.4%

Unsupported:
  Swift-only analogues: ...
  compiler-specific APIs: ...
  private/non-SDK APIs: ...
```

Do not inflate coverage statistics.

Every excluded API must have a reason code.

---

# 54. ERROR CLASSIFICATION

Use stable error codes.

Examples:

```text
E001 SDK_NOT_FOUND
E002 UNSUPPORTED_TYPE
E003 UNSUPPORTED_GENERIC
E004 UNSUPPORTED_CALLBACK
E005 PRIVATE_API
E006 NON_SDK_API
E007 LICENSE_REVIEW_REQUIRED
E008 INVALID_AST
E009 GENERATION_FAILURE
E010 RUNTIME_BINDING_FAILURE
E011 ABI_MISMATCH
E012 AVAILABILITY_MISMATCH
E013 THREADING_CONSTRAINT
E014 DOCUMENTATION_UNAVAILABLE
```

Document every error code.

---

# 55. DEVELOPER EXPERIENCE

The generated APIs must be discoverable in IDE autocomplete.

Developers should be able to navigate:

```text
Flutter code
 ↓
generated native declaration
 ↓
native symbol metadata
 ↓
platform documentation reference
```

The same concept should work for TypeScript where practical.

Generated source should be readable.

Do not generate minified source.

Use consistent names.

---

# 56. NATIVE NAME MAPPING

Native API names must remain traceable.

For example:

```text
android.content.Intent#setData
```

must never become an arbitrary:

```text
foo123()
```

Create deterministic names.

Preserve overload distinctions.

Use adapters only where the target language cannot represent the native signature directly.

---

# 57. RESERVED WORDS

Implement language-specific identifier escaping.

Examples:

Java:

```text
class
enum
default
```

Dart:

```text
class
switch
extension
```

TypeScript:

```text
class
interface
function
```

Do not accidentally produce invalid generated code.

---

# 58. OVERLOAD RESOLUTION

Support overloaded methods safely.

Do not generate ambiguous signatures.

Where the destination language cannot represent overloads naturally:

* generate deterministic suffixes
* or use typed named APIs
* document mapping

Preserve a metadata map from generated declaration → original native declaration.

---

# 59. CALLBACK ERROR HANDLING

A callback throwing an exception must not silently crash the native runtime.

Define:

```text
Dart exception
 ↓
generated boundary
 ↓
native error reporting
```

and equivalent React Native behavior.

Test:

* callback throws
* callback disposed
* native callback after JS object deletion
* callback called from wrong thread

---

# 60. PROPERTY MAPPING

Support:

```text
getters
setters
Objective-C properties
Java bean properties
Swift properties where accessible
```

Do not accidentally invoke methods repeatedly when a native field is expected.

Document whether the generated property is:

```text
read-only
read-write
computed
backed by native getter/setter
```

---

# 61. ENUM / FLAGS SUPPORT

Generate platform constants accurately.

For Android `IntDef`-style flags:

* preserve original values
* preserve semantic metadata
* optionally generate ergonomic wrappers
* never alter numeric values

For Objective-C enums/macros:

* parse official declarations where possible
* preserve names and numeric values
* record provenance

---

# 62. COLLECTION BRIDGING

Collection bridging must avoid unnecessary conversions.

Support:

```text
Java List
Java Map
Java Set
NSArray
NSDictionary
NSSet
Data/NSData
ByteBuffer
```

Design both:

```text
ergonomic conversion
```

and:

```text
native direct wrapper
```

paths.

For large buffers, measure performance.

---

# 63. THREAD-SAFE API SURFACE

Never assume:

```text
native API == thread safe
```

Use metadata and documentation where available.

Where thread semantics are unknown:

```text
threading = unspecified
```

not:

```text
thread-safe = true
```

---

# 64. NATIVE VERSION FEATURE FLAGS

Generated APIs should expose platform availability without requiring the developer to memorize every version.

Example conceptual API:

```dart
if (AndroidApi.isAtLeast(35)) {
  ...
}
```

or use generated availability annotations/helpers.

Do not generate fake APIs on unsupported OS versions.

---

# 65. TEST FIXTURE STRATEGY

Do not rely only on the latest installed platform SDK.

Create stable synthetic fixtures.

Examples:

```text
GenericClass<T>
NullableClass
OverloadedClass
CallbackInterface
EnumClass
NestedClass
AnnotatedClass
DeprecatedClass
ApiLevelClass
ThrowsClass
AsyncClass
```

Then add real platform fixture tests.

This separates generator regressions from external SDK changes.

---

# 66. FUZZ TESTING

Create parser fuzz tests.

Feed malformed:

* Java metadata
* Kotlin metadata
* Objective-C headers
* JSON IR
* annotations

The parser should fail safely and never crash the entire generator process.

---

# 67. SNAPSHOT COMPATIBILITY

Create snapshots of selected official SDK APIs.

Do not store restricted Apple SDK source files.

Store only the minimum legal metadata needed for tests.

For Apple tests, prefer synthetic headers or locally generated test fixtures.

For Android, follow the applicable SDK/content licenses when storing fixtures.

---

# 68. WEBSITE

Create a small professional static website under:

```text
website/
```

It must be deployable using GitHub Pages.

GitHub Pages can publish a static site from a repository and can use GitHub Actions for deployment.

The site should be:

* static
* fast
* responsive
* accessible
* SEO-friendly
* no backend
* no mandatory analytics
* no tracking by default
* easy to host on GitHub Pages
* compatible with a custom domain later

---

# 69. WEBSITE DESIGN

Create a polished developer-tool landing page.

Style:

```text
modern developer infrastructure
clean
technical
credible
minimal
fast
```

Avoid:

* excessive animations
* fake testimonials
* fake customer logos
* fake GitHub stars
* fake benchmark numbers
* fake compatibility claims
* stock imagery
* marketing exaggeration

Hero:

```text
Use Native APIs Directly.
Generate the Binding. Not the Boilerplate.

Automatically generate typed Android and iOS native API bindings for Flutter and React Native.
```

Primary buttons:

```text
Get Started
View on GitHub
Read Documentation
```

---

# 70. WEBSITE SECTIONS

Include:

## Hero

What the project is.

## Problem

Explain repetitive:

* MethodChannel code
* JNI boilerplate
* Objective-C wrappers
* TurboModule boilerplate
* native synchronization
* API version maintenance

## Solution

Explain:

```text
SDK → IR → Generator → Native Binding
```

## Architecture

Show:

```text
Android SDK → Android parser → IR → Dart/JNI
                                   ↓
                                   C++/JSI

Apple SDK → Clang/Swift metadata → IR → Dart/ObjC
                                     ↓
                                     C++/JSI
```

## Flutter

Example code.

## React Native

Example code.

## Versioning

Explain:

```bash
native-api-bindgen update
```

## Coverage

Show real generated statistics only.

## Legal & Source Policy

Explain official-source-first and no private API support.

## Performance

Show measured benchmarks only.

## Roadmap

Keep future work clearly labeled.

## FAQ

Questions such as:

* Is this a replacement for MethodChannel?
* Does it support private APIs?
* Does it copy Apple SDKs?
* Will app size increase?
* Does it work with React Native New Architecture?
* Can it generate new Android/iOS versions automatically?
* Does it require an internet connection?
* Is it free/open source?

## Footer

Include:

* GitHub
* documentation
* license
* security
* contributing
* legal/source policy

---

# 71. SEO

Make the website genuinely SEO-friendly.

Use unique:

```html
<title>
<meta name="description">
<link rel="canonical">
```

Use semantic HTML.

Create:

```text
robots.txt
sitemap.xml
site.webmanifest
```

Use Open Graph and social preview metadata.

Create JSON-LD structured data appropriate to the actual site, such as:

```text
SoftwareSourceCode
WebSite
TechArticle
```

Do NOT create fake:

```text
aggregateRating
review
customer rating
```

Use real project information only.

Natural target topics:

* Flutter native API bindings
* Flutter JNI
* Dart Android interop
* Flutter Objective-C interop
* React Native native API bindings
* React Native JSI
* Android API code generation
* iOS API code generation
* native SDK binding generator
* Android/iOS code generation
* cross-platform native bindings

Avoid keyword stuffing.

---

# 72. WEBSITE SEO PAGES

Create separate crawlable pages for:

```text
/
getting-started
/architecture
/flutter
/react-native
/android
/ios
/versioning
/compatibility
/legal
/faq
```

Each page needs:

* unique title
* unique meta description
* canonical URL
* clear H1
* semantic H2 structure
* meaningful internal links

---

# 73. GITHUB PAGES

Configure:

```text
.github/workflows/website.yml
```

Use official GitHub Pages deployment workflow patterns.

Build the static site and deploy it to GitHub Pages.

Support a repository project-site path and make the site configuration easy to switch to a custom domain later.

Do not require a custom domain.

GitHub Pages officially supports project sites and custom domains.

---

# 74. GITHUB REPOSITORY QUALITY

Create the recommended public-repository health files:

```text
README.md
LICENSE
CONTRIBUTING.md
CODE_OF_CONDUCT.md
SECURITY.md
SUPPORT.md
```

GitHub specifically recommends repository health/community files including LICENSE, CONTRIBUTING and CODE_OF_CONDUCT.

Create:

```text
.github/ISSUE_TEMPLATE/
.github/pull_request_template.md
```

Issue types:

```text
bug
feature
generator coverage
platform compatibility
legal/source issue
documentation
```

---

# 75. README

The README must explain within the first screen:

```text
What it is
Why it exists
What platforms are supported
What it does NOT support
Installation
First command
Architecture
Legal/source policy
Current status
```

Example:

```bash
dart pub global activate native_api_bindgen
```

or the appropriate package command once the final distribution mechanism is chosen.

Do not advertise APIs as supported until tests prove support.

---

# 76. EXAMPLE FLUTTER APP

Build an example demonstrating:

```text
Android:
Intent
Uri
Context
Activity

iOS:
Foundation object
UIKit object
```

Use small, understandable examples.

Do not create a fake "every API" example.

---

# 77. EXAMPLE REACT NATIVE APP

Build equivalent examples.

Demonstrate:

```text
Android native object
iOS native object
sync method
async method
callback
native lifecycle
```

Use New Architecture.

---

# 78. API NAMING / BRANDING

Do not imply affiliation with:

* Google
* Android
* Apple
* React
* Meta
* Flutter

Use statements such as:

> "This project is an independent open-source project and is not affiliated with or endorsed by Google, Apple, Meta, or the Dart/Flutter teams."

Include appropriate trademark attribution.

Do not use official platform logos as though they are project logos.

---

# 79. WEBSITE LEGAL DISCLAIMER

Add a concise disclaimer:

```text
Native API Bindgen is an independent open-source project.
It is not affiliated with or endorsed by Google, Apple, Meta,
or the Dart/Flutter project.

Platform SDKs, documentation, trademarks, and other third-party
materials remain the property of their respective owners and are
subject to their applicable licenses and terms.
```

Keep it factual.

---

# 80. NO FABRICATED CLAIMS

Never write:

```text
100% of Android APIs
100% of iOS APIs
zero overhead
zero binary size
faster than native
App Store approved
officially supported by Apple
officially supported by Google
```

unless objectively proven and appropriately qualified.

Use:

```text
experimental
partial
supported
tested
measured
not yet supported
```

accurately.

---

# 81. PUBLIC ROADMAP

Create:

```text
docs/roadmap.md
```

Potential roadmap:

### Phase 1

Android Java API generation

### Phase 2

Android callbacks/generics/annotations

### Phase 3

Objective-C/iOS

### Phase 4

Flutter production runtime

### Phase 5

React Native New Architecture

### Phase 6

Swift-only API adapters

### Phase 7

advanced native UI

Do not represent roadmap items as completed features.

---

# 82. PROJECT DEVELOPMENT PHASES

Implement incrementally.

## Phase A — Foundation

Create:

* monorepo
* CLI
* IR
* configuration
* diagnostics
* logging
* version model

## Phase B — Android

Implement:

* SDK detection
* API parsing
* IR generation
* Java/JNI mapping
* Dart generation
* basic runtime
* tests

## Phase C — Android advanced

Implement:

* annotations
* generics
* callbacks
* lifecycle
* threading
* async
* permissions
* coverage reports

## Phase D — Apple

Implement:

* Xcode SDK detection
* Objective-C parser
* IR
* Dart bindings
* Objective-C runtime
* availability
* tests

## Phase E — Swift

Implement supported Swift bridge scenarios incrementally.

## Phase F — React Native

Implement:

* TypeScript representation
* Codegen specifications
* JSI
* C++
* Android
* iOS
* native object handles

## Phase G — Distribution

Implement:

* package metadata
* releases
* CHANGELOG
* documentation
* examples

## Phase H — Website

Implement:

* static website
* SEO
* GitHub Pages
* legal/source policy
* documentation navigation

---

# 83. DO NOT OVER-ENGINEER THE FIRST VERTICAL SLICE

Before attempting thousands of APIs, prove this complete flow:

```text
Android SDK
 ↓
Parser
 ↓
IR
 ↓
Dart generation
 ↓
JNI
 ↓
Real Android app
 ↓
Native API
```

Then prove:

```text
Android SDK
 ↓
IR
 ↓
TypeScript/JSI
 ↓
Real React Native app
 ↓
Native API
```

Then prove equivalent iOS flows.

Only after the vertical slice passes should large-scale API generation begin.

---

# 84. FIRST VERTICAL-SLICE APIS

Android:

```text
android.content.Intent
android.net.Uri
android.os.Bundle
android.os.Handler
android.os.Looper
android.content.Context
```

Apple:

```text
Foundation.NSObject
Foundation.NSString
Foundation.NSArray
Foundation.NSDictionary
UIKit.UIView
UIKit.UIViewController
```

Do not choose APIs only because they are easy.

Choose a mixture of:

* simple classes
* inheritance
* constants
* overloads
* callbacks
* nullable values
* availability

---

# 85. ACCEPTANCE CRITERIA

The project is NOT complete merely because files are generated.

It must satisfy:

## Generation

```text
Given a supported local SDK,
generator runs successfully.
```

## Correctness

```text
Generated API matches native signature.
```

## Runtime

```text
Generated binding executes against real platform API.
```

## Lifecycle

```text
Native references are released correctly.
```

## Callbacks

```text
Callbacks are delivered correctly.
```

## Availability

```text
Unsupported API versions fail safely.
```

## Documentation

```text
Generated docs show provenance and availability.
```

## Legal

```text
Restricted SDK artifacts are not accidentally redistributed.
```

## Reproducibility

```text
Same input → same generated output.
```

## Size

```text
Unused generated APIs do not force the entire SDK wrapper into the app.
```

## CI

```text
Automated tests pass.
```

## Website

```text
GitHub Pages build succeeds.
```

---

# 86. TEST THE LEGAL GUARDRAILS

Create automated tests/checks that fail when the repository contains:

```text
*.framework
*.xcframework
Apple SDK paths
known SDK system headers copied from Xcode
large copied documentation dumps
private Apple framework binaries
```

Also scan for:

```text
license headers
attribution requirements
unknown third-party files
```

Do not build a scanner based only on filename.

Use content/signature checks where appropriate.

---

# 87. LEGAL REVIEW CHECKPOINT

Before the first public release:

Generate:

```text
LEGAL_RELEASE_REPORT.md
```

containing:

```text
Project license
Third-party licenses
Android source/material usage
Apple SDK usage model
Documentation redistribution model
Generated-code policy
Trademark policy
Private API policy
Known review items
```

Mark uncertain items:

```text
LEGAL_REVIEW_REQUIRED
```

Do not falsely mark them compliant.

---

# 88. DOCUMENT OFFICIAL SOURCES

Create:

```text
docs/sources/official-sources.md
```

with categorized references to official sources.

At minimum include official materials for:

Flutter/Dart:

* Dart Java interop / JNI
* Dart Objective-C/Swift interop
* Flutter native FFI/build hooks

Android:

* Android developer API reference
* Android SDK/tooling
* Android legal/content licensing
* Android annotations/API level information

Apple:

* Apple Developer Agreements and Guidelines
* Apple Developer documentation for Objective-C/Swift interoperability
* availability
* Xcode/SDK tooling information

React Native:

* New Architecture
* JSI
* Codegen
* Turbo Native Modules
* library architecture

GitHub:

* GitHub Pages
* GitHub Actions deployment
* repository licensing/community health

Whenever official documentation changes, update the source registry.

---

# 89. SOURCE VALIDATION

Build a source-validation process.

Every parser/generator subsystem must identify:

```text
official source
source version
source timestamp or revision where appropriate
```

No unsupported claim should enter the generated API database without provenance.

---

# 90. CHANGE MANAGEMENT

Any change to:

* IR
* type mapping
* ownership model
* generated API
* parser behavior
* license classification
* platform support

must have tests.

For generator changes:

```text
parser test
IR test
golden test
integration test
```

when applicable.

---

# 91. COMMIT QUALITY

Use meaningful commits.

Examples:

```text
feat(ir): add generic type model
feat(android): parse API-level metadata
feat(flutter): generate JNI bindings
feat(rn): add JSI native object wrapper
test(android): add callback fixtures
fix(ios): preserve availability metadata
docs(legal): clarify Apple SDK redistribution policy
```

Do not use giant unclear commits.

---

# 92. CODE QUALITY RULES

Use:

* strict type checking
* formatter
* linter
* static analysis
* documentation comments for public interfaces
* minimal hidden global state
* dependency inversion
* deterministic generators
* structured diagnostics
* testable components

Avoid:

* reflection as the core architecture
* global registries containing every symbol
* runtime scraping
* string-based class lookup when compile-time generation is possible
* manually duplicating thousands of bindings
* silently swallowing unsupported APIs

---

# 93. GENERATED CODE MARKERS

Every generated file should begin with a marker:

```text
// GENERATED CODE - DO NOT MODIFY BY HAND.
// Generated by native-api-bindgen X.Y.Z
// Source SDK: ...
```

Never ask users to manually edit generated files.

Provide extension points in separate source files.

---

# 94. CUSTOMIZATION

Support user configuration:

```yaml
platform:
  android:
    sdk: auto
    minApi: 24
    include:
      - android.content
      - android.net

  ios:
    sdk: auto
    frameworks:
      - Foundation
      - UIKit

targets:
  flutter: true
  reactNative: true

generation:
  mode: strict-native
  docs: summary
  annotations: preserve
  callbacks: true
```

Do not require generating the entire platform.

Users should be able to generate only needed namespaces/frameworks.

---

# 95. SELECTIVE GENERATION

Support:

```bash
native-api-bindgen generate android --package android.content
```

and:

```bash
native-api-bindgen generate ios --framework Foundation
```

Also:

```bash
native-api-bindgen generate android --class android.content.Intent
```

and dependency-aware generation:

```bash
native-api-bindgen generate --entry android.content.Intent
```

The generator should automatically include required referenced types.

---

# 96. DEPENDENCY GRAPH

Build an API dependency graph.

Example:

```text
Intent
 ├── Context
 ├── Uri
 └── Bundle
```

Use it to determine:

* generated dependencies
* module boundaries
* tree-shaking opportunities
* generation order
* diagnostics

Do not generate unrelated APIs unnecessarily.

---

# 97. GRAPH EXPORT

Provide:

```bash
native-api-bindgen graph android.content.Intent
```

Output text or JSON:

```text
Intent
 ├─ Uri
 ├─ Bundle
 └─ ComponentName
```

Useful for debugging large generated APIs.

---

# 98. DOCUMENTATION SITE FOR GENERATED API

The main marketing website is separate from generated API documentation.

Create architecture supporting eventually:

```text
docs/
generated-docs/
```

Potential future static API explorer:

```text
/api/android/android.content.Intent
/api/ios/Foundation/NSObject
```

Do not implement a huge API explorer until the generator is stable.

---

# 99. WEBSITE PERFORMANCE

Target:

* minimal JS
* no heavy framework unless justified
* compressed assets
* lazy images
* semantic HTML
* accessible navigation
* system fonts or legally safe web fonts
* no blocking scripts
* no unnecessary tracking

Run a basic performance check in CI.

---

# 100. WEBSITE ACCESSIBILITY

Target:

* keyboard navigation
* visible focus
* semantic headings
* labels
* sufficient contrast
* reduced motion support
* alt text
* accessible code blocks
* mobile responsive layout

Do not use motion as the primary way to communicate information.

---

# 101. WEBSITE CONTENT ACCURACY

All feature claims must be traceable to actual implementation status.

Include a visible:

```text
Project Status
```

with:

```text
Experimental
Alpha
Beta
Stable
```

Do not claim Stable until release criteria are met.

---

# 102. PACKAGE README BADGE POLICY

Badges may include:

* CI
* package version
* license
* supported platform
* documentation

Do not create fake:

```text
coverage 100%
downloads 1M+
performance 10x
```

unless generated automatically from real data.

---

# 103. RELEASE PROCESS

Implement:

```text
release-check.yml
release.yml
```

Release pipeline:

```text
format
lint
test
golden
integration
license audit
security audit
size test
generate sample bindings
package validation
documentation build
website build
release notes
```

Only release when all required checks pass.

---

# 104. CHANGELOG

Use Keep-a-Changelog style.

Separate:

```text
Added
Changed
Deprecated
Removed
Fixed
Security
Legal/Source policy
```

---

# 105. SEMVER

Follow semantic versioning for the generator/runtime APIs.

Platform API versions are independent.

Do not bump the project major version merely because Android/iOS added an API.

Do bump when the project's own generated API contract or runtime behavior introduces a breaking change according to the defined policy.

Document this in:

```text
docs/versioning.md
```

---

# 106. REACT NATIVE COMPATIBILITY

Support New Architecture first.

Document legacy architecture separately.

Do not let compatibility code pollute the primary architecture unnecessarily.

When React Native's official APIs change, update the generator against the tested compatibility matrix.

---

# 107. FLUTTER COMPATIBILITY

Use currently supported native interop mechanisms.

Do not build a new architecture around deprecated Flutter mechanisms.

Where Flutter Plugin API is genuinely needed, isolate it behind a small adapter.

Document why that API is required.

---

# 108. OBSERVABILITY

The CLI should produce structured logs.

Example:

```text
INFO SDK detected
INFO parsing API
INFO generated symbol
WARN unsupported feature
ERROR generation failed
```

Support:

```bash
--verbose
--quiet
--json
```

JSON mode should be machine-readable.

---

# 109. DEBUG COMMANDS

Support:

```bash
native-api-bindgen inspect <symbol>
native-api-bindgen explain <symbol>
native-api-bindgen why-generated <symbol>
native-api-bindgen why-skipped <symbol>
```

Example:

```text
Why skipped:
  Swift-only associated type
  No stable target-language mapping
```

This is important for developer trust.

---

# 110. "WHY GENERATED" PROVENANCE

For any generated function/class, a developer should be able to determine:

```text
Original native symbol
SDK version
Parser
IR node
Generator
Output files
Runtime adapter
Official source reference
```

This should be central to the project.

---

# 111. FINAL PROJECT PRINCIPLE

Do not optimize for:

> "Generate the maximum number of lines of code."

Optimize for:

> "Generate the maximum amount of correct, traceable, supported native API surface with minimum manual glue code."

Correctness > coverage.

Legal compliance > copied documentation.

Determinism > convenience.

Native semantics > fake abstraction.

Measured performance > marketing claims.

---

# 112. IMPLEMENTATION INSTRUCTIONS TO CLAUDE CODE

Start by inspecting the repository.

If the repository is empty, initialize the project structure.

Do not ask the user to manually create files that you can create yourself.

First create:

```text
architecture document
technical design document
implementation plan
source policy
license policy
test strategy
```

Then implement the smallest complete vertical slice.

After every major implementation stage:

1. run formatting
2. run static analysis
3. run unit tests
4. run generation tests
5. run integration tests where available
6. inspect generated output
7. inspect binary-size implications
8. update documentation
9. update compatibility information

Do not leave placeholder functions pretending to work.

When a feature cannot yet be implemented:

* create a clear diagnostic
* create a tracked limitation
* add a test proving the diagnostic
* document the reason

Do not silently generate incorrect bindings.

---

# 113. FIRST DELIVERABLE

The first implementation milestone must produce a working Android vertical slice:

```text
Android SDK
 ↓
Parser
 ↓
IR
 ↓
Dart generator
 ↓
JNI runtime
 ↓
Flutter example
 ↓
Real Android API call
```

Include:

```text
Intent
Uri
Bundle
Context
Activity
```

plus:

* inheritance
* constants
* nullable parameter
* method overload
* API availability
* documentation metadata
* one callback/listener example
* lifecycle test
* generator golden test
* integration test

Then implement the equivalent React Native vertical slice.

Then begin iOS.

Do NOT attempt to generate the entire Android/iOS SDK before proving the architecture.

---

# 114. FINAL OUTPUT REQUIRED FROM CLAUDE CODE

At completion of the current implementation stage, provide:

```text
1. What was implemented
2. Repository structure
3. Supported APIs
4. Unsupported APIs/features
5. Tests added
6. Tests executed
7. Test results
8. Generated artifact statistics
9. Coverage statistics
10. Binary-size measurements
11. Legal/source checks
12. Security checks
13. Website status
14. Known limitations
15. Next recommended implementation stage
```

Every statistic must come from actual execution.

Never invent numbers.

---

# 115. MOST IMPORTANT CONSTRAINT

Never substitute a hand-written implementation for the generated architecture merely to make a demo pass.

The ultimate goal is:

```text
Official platform SDK
        ↓
Automatic discovery
        ↓
Canonical IR
        ↓
Automatic code generation
        ↓
Flutter / React Native
        ↓
Direct native interop
```

A developer should eventually be able to install/update the generator and run:

```bash
native-api-bindgen update
```

to regenerate bindings for the locally installed supported Android/iOS SDK versions.

That is the defining feature of this project.

Begin implementation now.
