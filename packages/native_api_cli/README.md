<p align="center">
  <img src="https://raw.githubusercontent.com/lkrjangid1/native-api-bindgen/main/docs/images/logo.svg" alt="native-api-bindgen logo" width="96">
</p>

<h1 align="center">native_api_bindgen</h1>

<p align="center">
  <strong>Use native APIs directly. Generate the binding, not the boilerplate.</strong>
</p>

<p align="center">
  <a href="https://pub.dev/packages/native_api_bindgen"><img src="https://img.shields.io/pub/v/native_api_bindgen?include_prereleases" alt="pub version"></a>
  <a href="https://github.com/lkrjangid1/native-api-bindgen/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0"></a>
</p>

`native-api-bindgen` reads the Android and iOS SDKs already installed on your machine and generates **typed bindings** for them:

- **Flutter / Dart:** over [`package:jni`](https://pub.dev/packages/jni) (Android) and [`package:objective_c`](https://pub.dev/packages/objective_c) (iOS).
- **React Native / TypeScript:** New Architecture, over JSI + C++ with JNI (Android) or Objective-C++ (iOS).

No MethodChannel, no hand-written plugin per API, no copied SDK files.

> **Beta (`0.1.0-beta.1`).**
> - Flutter and React Native work end to end on both Android and iOS.
> - Tested on an Android emulator and an iOS simulator, not yet on physical devices.
> - Generated APIs, configuration and output may still change between beta releases.

## Install

```bash
dart pub global activate native_api_bindgen
# or, a prebuilt binary for macOS / Linux:
brew install lkrjangid1/tap/native-api-bindgen

native-api-bindgen doctor      # shows the Android SDK, JDK, Xcode and libclang it found
```

| You want | You need |
|---|---|
| Android bindings | Android SDK with a platform (e.g. `android-36`), a JDK |
| iOS bindings | macOS with Xcode (libclang and the iOS SDK come with it) |
| Flutter target | Flutter 3.32+ (tested with 3.41.9) |
| React Native target | React Native 0.76+ with the New Architecture |

## Quick start (Flutter)

**1. Configure.** In your app directory:

```bash
native-api-bindgen init        # writes native_api_bindgen.yaml
```

List only what you need; dependencies follow up to `depth`. Generating a whole SDK is never implicit.

```yaml
# native_api_bindgen.yaml
platform:
  android:
    platform: "36"
    minApi: 24                   # newer APIs get runtime availability guards
    entries:
      - android.content.Intent
      - android.net.Uri
    depth: 0
  ios:
    minVersion: "15.0"
    frameworks: [Foundation, UIKit]
    classes: [UIDevice, UIView]
    depth: 0

targets:
  flutter: true
  reactNative: false

output:
  dir: lib/src/generated
```

**2. Add the runtime dependencies** to your app's `pubspec.yaml`:

```yaml
dependencies:
  jni: ^1.0.3                    # Android
  jni_flutter: ^1.0.3            # Android: application Context / current Activity
  objective_c: 9.5.0             # iOS
  native_api_runtime: ^0.1.0-beta.1
  native_api_ui: ^0.1.0-beta.1   # optional: show native views in the widget tree
```

**3. Generate.**

```bash
native-api-bindgen generate flutter        # Android → Dart
native-api-bindgen generate ios            # iOS → Dart
```

Add `lib/src/generated/` and `.native_api_bindgen/` to `.gitignore`. Generated bindings are derived from your local SDK and stay in your project.

**4. Call native APIs.**

```dart
// Android. Import with a prefix: names such as View or Text clash with Flutter.
import 'package:jni/jni.dart';
import 'src/generated/bindings.dart' as android;

final uri = android.Uri.parse('https://example.com/p?q=1'.toJString())!;
final intent = android.Intent.new$String$Uri(
    android.Intent.ACTION_VIEW.toJString(), uri);

// Implement a Java interface in Dart.
final handler = android.Handler.new$Looper(android.Looper.getMainLooper()!);
handler.post(android.Runnable.implement(
    android.$Runnable(run: () => print('main looper'))));
```

```dart
// iOS
import 'src/generated/apple.dart' as ios;

print(ios.UIDevice.currentDevice.systemName.toDartString());

try {
  ios.NSFileManager.defaultManager.contentsOfDirectoryAtPath('/missing'.toNSString());
} on ios.NativeObjCError catch (e) {
  print(e.domain);               // NSCocoaErrorDomain
}
```

## React Native

```bash
native-api-bindgen generate react-native           # every configured platform
native-api-bindgen generate react-native-android   # Android → TypeScript + C++ (JSI → JNI)
native-api-bindgen generate react-native-ios       # iOS → TypeScript + ObjC++ (macOS only)
```

```ts
const intent = Intent.new$String$Uri(Intent.ACTION_VIEW, Uri.parse('https://example.com'));
const greeting = await greeter.greetLater(20n);          // Kotlin suspend → Promise
```

See the [React Native guide](https://github.com/lkrjangid1/native-api-bindgen/tree/main/docs/react-native).

## Commands

| Command | What it does |
|---|---|
| `doctor` | Detects the Android SDK, JDK, Xcode, iOS SDK and libclang |
| `init` | Writes a starter `native_api_bindgen.yaml` |
| `detect`, `inspect` | Lists installed SDKs and toolchains; shows an SDK summary or a symbol's IR |
| `generate <target>` | `flutter`, `ios`, `react-native`, `react-native-android`, `react-native-ios` |
| `update`, `diff` | Regenerates after an SDK update; diffs the API of two installed platform versions |
| `coverage` | What was generated vs. discovered, grouped by reason code |
| `why-generated`, `why-skipped`, `explain` | Traces one symbol: why it exists, or why not (e.g. `E004`) |
| `docs` | Local API reference in `generated-docs/` (metadata + official links) |
| `graph` | Dependency graph of a type |
| `audit-license` | Blocks accidental commits of SDK artifacts |
| `verify-reproducible` | Regenerates and checks the output is byte-identical |
| `clean` | Removes generated output and state |

Global flags: `--project`, `--config`, `--json`, `--verbose`, `--quiet`.
Exit codes: `0` ok, `1` failure (including a license BLOCK), `2` not implemented (`E015`), `64` usage error.

```bash
native-api-bindgen why-skipped 'android.app.Activity#onCreate'
native-api-bindgen why-generated 'android.content.Intent#getData()'
native-api-bindgen explain 'UIDevice#systemName'
```

## Packages

| Package | Role |
|---|---|
| **`native_api_bindgen`** | This CLI |
| [`native_api_runtime`](https://pub.dev/packages/native_api_runtime) | Runtime used by generated Dart code (availability guards, errors, coroutines) |
| [`native_api_ui`](https://pub.dev/packages/native_api_ui) | Flutter plugin that hosts native views created through bindings |
| [`native_api_ir`](https://pub.dev/packages/native_api_ir), [`native_api_core`](https://pub.dev/packages/native_api_core), [`native_api_generator`](https://pub.dev/packages/native_api_generator) | IR, configuration and shared generation (internal) |
| [`native_api_android`](https://pub.dev/packages/native_api_android), [`native_api_ios`](https://pub.dev/packages/native_api_ios) | SDK extraction (internal) |
| `native_api_flutter_*`, `native_api_react_native_*` | Per-target emitters (internal) |

You only need `native_api_bindgen` (globally activated) plus `native_api_runtime` / `native_api_ui` in your app.

## What it does not do

- No private or hidden APIs: non-SDK Android APIs and private Objective-C selectors are never generated.
- No SDK redistribution: generation runs against locally installed SDKs.
- No copied documentation prose: generated docs hold metadata and links to official references.
- No claim of complete coverage: `coverage` and `why-skipped` show what was not generated, and why.

## Links

- [Repository and full README](https://github.com/lkrjangid1/native-api-bindgen)
- [Getting started](https://github.com/lkrjangid1/native-api-bindgen/tree/main/docs/getting-started)
- [Example apps](https://github.com/lkrjangid1/native-api-bindgen/tree/main/examples) (Flutter Android / iOS, React Native)
- [Reason codes](https://github.com/lkrjangid1/native-api-bindgen/blob/main/docs/error-codes.md)
- [Issues](https://github.com/lkrjangid1/native-api-bindgen/issues)

Native API Bindgen is an independent open-source project, not affiliated with or endorsed by Google, Apple, Meta, or the Dart/Flutter project. Apache-2.0 for the project's own source; platform SDKs and output derived from them are subject to their own terms.
