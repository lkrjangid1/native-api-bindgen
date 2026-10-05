# native-api-bindgen

**Automatically generated bindings for supported public platform SDK APIs** — for Flutter/Dart today, React Native/TypeScript next.

> Project status: **Experimental (pre-alpha).** Only the Android → Flutter vertical slice is implemented. Nothing here is production-ready, and no API is advertised as supported until a test proves it.

## What it is

`native-api-bindgen` reads the platform SDK that is already installed on your machine (for Android: `android.jar`, `api-versions.xml`, `annotations.zip`), converts it into a canonical, JSON-serializable **Native IR**, and generates typed bindings from that IR. For Flutter on Android the output is plain Dart that calls Java directly through [`package:jni`](https://pub.dev/packages/jni) — no MethodChannel, no hand-written glue.

## Why it exists

Calling a single platform API from Flutter or React Native usually means writing a MethodChannel / TurboModule, JNI or Objective-C glue, and then maintaining it every time the platform SDK changes. This project generates that layer from first-party SDK metadata, keeps every generated symbol traceable to the native symbol it came from, and tells you precisely what it could not generate and why.

## Platform support (current, tested)

| Source platform | Target | Status |
|---|---|---|
| Android (Java APIs from `android.jar`) | Flutter / Dart via `package:jni` | Experimental — vertical slice (see [docs/android](docs/android/README.md)) |
| Android | React Native (JSI/TurboModules) | Not yet implemented |
| iOS (Objective-C headers) | Flutter / React Native | Not yet implemented |
| Swift-only APIs | any | Not yet implemented |

## What it does NOT do

- It does **not** expose private Apple APIs or hidden/non-SDK Android APIs as supported APIs.
- It does **not** vendor, copy or redistribute platform SDKs. Generation runs against SDKs installed locally.
- It does **not** copy platform documentation prose; generated docs contain metadata and links to official references.
- It does **not** claim complete coverage. `native-api-bindgen coverage` reports what was generated and gives a reason code for everything that was not.

## Installation

The CLI is a Dart package (not yet published to pub.dev). From a clone:

```bash
dart pub get
dart pub global activate --source path packages/native_api_cli
native-api-bindgen doctor
```

Once published: `dart pub global activate native_api_bindgen`. Step-by-step guide: [docs/getting-started](docs/getting-started/README.md).

## First commands

```bash
native-api-bindgen doctor                       # what SDKs/toolchains are installed
native-api-bindgen init                         # write native_api_bindgen.yaml
native-api-bindgen generate flutter --entry android.content.Intent
native-api-bindgen coverage
native-api-bindgen why-skipped 'android.app.Activity#onCreate'
```

```dart
import 'package:jni/jni.dart';
import 'src/generated/bindings.dart';

final uri = Uri.parse('https://example.com'.toJString());
final intent = Intent.new$String$Uri(Intent.ACTION_VIEW.toJString(), uri);
print(intent.getData()); // https://example.com  (calls android.content.Intent#getData via JNI)
```

## Architecture

```
Android SDK (android.jar + api-versions.xml + annotations.zip)
        ↓  native_api_android (pure-Dart classfile parser)
Canonical Native IR (native_api_ir)  ── JSON for diagnostics
        ↓  validation / dependency graph / type mapping (native_api_generator)
Dart + package:jni bindings (native_api_flutter_android)
        ↓
Flutter app → JNI → Android framework
```

See [docs/architecture/overview.md](docs/architecture/overview.md) and [docs/technical-design.md](docs/technical-design.md).

## Legal / source policy

Platform facts come only from first-party SDK artifacts installed locally, enriched by first-party metadata. See [docs/legal/source-provenance.md](docs/legal/source-provenance.md), [docs/legal/android.md](docs/legal/android.md) and [docs/legal/apple.md](docs/legal/apple.md). `native-api-bindgen audit-license` blocks accidental redistribution of SDK artifacts. These documents are engineering policy, not legal advice.

This project is an independent open-source project and is not affiliated with or endorsed by Google, Apple, Meta, or the Dart/Flutter teams. Android is a trademark of Google LLC. Apple and iOS are trademarks of Apple Inc., registered in the U.S. and other countries. Flutter and Dart are trademarks of Google LLC. React and React Native are trademarks of Meta Platforms, Inc.

## Current status and roadmap

See [docs/roadmap.md](docs/roadmap.md) and [CHANGELOG.md](CHANGELOG.md).

## License

Apache-2.0 for the project's own source (see [LICENSE](LICENSE) and [NOTICE](NOTICE)). Platform SDKs, their documentation and generated output derived from them are subject to their own terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
