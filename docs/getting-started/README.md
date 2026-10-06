# Getting started (Flutter on Android)

> Beta (`0.1.0-beta.1`). Generated bindings are derived from the Android SDK on your machine and are kept local by default.

## Prerequisites

- Flutter (Dart ≥ 3.9) — see `docs/compatibility/matrix.md` for tested versions
- Android SDK with at least one platform installed (`sdkmanager "platforms;android-36"`); `ANDROID_HOME` or the default Android Studio location
- A JDK only if you run the fixture/runtime tests of this repository

## 1. Install the CLI

Pick one:

| From | Command | Needs |
|---|---|---|
| [pub.dev](https://pub.dev/packages/native_api_bindgen) | `dart pub global activate native_api_bindgen` | Dart 3.9+ (Flutter's Dart works) |
| Homebrew | `brew install lkrjangid1/tap/native-api-bindgen` | macOS (arm64, x64) or Linux (x64, arm64) |
| Source | `dart pub get && dart pub global activate --source path packages/native_api_cli` | a clone of this repository |

Inside this repository you can also use `dart run native_api_bindgen <command>`.

## 2. Check your machine

```bash
native-api-bindgen --project /path/to/your_app doctor
```

## 3. Configure

```bash
native-api-bindgen --project /path/to/your_app init
```

Edit `native_api_bindgen.yaml`: list the classes you need under `platform.android.entries` (dependency-aware) or `classes`/`include`. Generating the whole SDK is never implicit.

## 4. Add runtime dependencies to your app

```yaml
dependencies:
  jni: ^1.0.3
  jni_flutter: ^1.0.3        # to obtain the application Context / Activity
  native_api_runtime: ^0.1.0-beta.1
```

## 5. Generate and use

```bash
native-api-bindgen --project /path/to/your_app generate flutter
```

```dart
import 'package:jni/jni.dart';
import 'package:jni_flutter/jni_flutter.dart' as jf;
// Import with a prefix: Android names such as View, Text or Color would
// otherwise clash with Flutter widgets.
import 'src/generated/bindings.dart' as android;

final ctx = jf.androidApplicationContext.as(android.Context.type);
print(ctx.getPackageName()!.toDartString(releaseOriginal: true));

final intent = android.Intent.new$String$Uri(
  android.Intent.ACTION_VIEW.toJString(),
  android.Uri.parse('https://example.com'.toJString()),
);
```

Add `lib/src/generated/` and `.native_api_bindgen/` to `.gitignore`.

## 6. Understand what you got

```bash
native-api-bindgen --project /path/to/your_app coverage
native-api-bindgen --project /path/to/your_app why-generated 'android.content.Intent#setData'
native-api-bindgen --project /path/to/your_app why-skipped 'android.app.Activity#onCreate'
```

A complete working app is in `examples/flutter/android_slice`.
