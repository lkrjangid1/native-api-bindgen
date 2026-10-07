# Official source registry

<!-- description: The first-party sources behind each native-api-bindgen parser and generator: local SDK inputs and official Flutter, Android, Apple and React Native docs. -->

Every parser/generator subsystem must name its first-party source. Links were last reviewed 2026-10-05; `tools/check_links.dart` validates them in CI (`website.yml`/`ci.yml` link job).

## Local machine-readable inputs (authoritative for signatures)

| Subsystem | Source | Version identification |
|---|---|---|
| Android signatures | `$ANDROID_HOME/platforms/android-N/android.jar` (SDK Platform package) | `source.properties` → `AndroidVersion.ApiLevel`, `Pkg.Revision`, `AndroidVersion.ExtensionLevel` |
| Android availability | `platforms/android-N/data/api-versions.xml` | same platform package |
| Android external annotations | `platforms/android-N/data/annotations.zip` | same platform package |
| Apple (planned) | Xcode SDK headers via `xcrun --sdk iphoneos --show-sdk-path`, Clang AST | `xcrun --show-sdk-version`, `xcodebuild -version` |

## Flutter / Dart
- Java/Kotlin interop (JNI, jnigen): https://dart.dev/interop/java-interop
- Objective-C/Swift interop: https://dart.dev/interop/objective-c-interop
- C interop (`dart:ffi`): https://dart.dev/interop/c-interop
- Flutter native code binding / build hooks: https://docs.flutter.dev/platform-integration/bind-native-code
- `package:jni`: https://pub.dev/packages/jni
- `package:jnigen`: https://pub.dev/packages/jnigen
- `package:jni_flutter`: https://pub.dev/packages/jni_flutter

## Android
- API reference: https://developer.android.com/reference
- SDK Platform releases: https://developer.android.com/tools/releases/platforms
- API levels: https://developer.android.com/guide/topics/manifest/uses-sdk-element
- Non-SDK interface restrictions: https://developer.android.com/guide/app-compatibility/restrictions-non-sdk-interfaces
- AndroidX annotations: https://developer.android.com/reference/androidx/annotation/package-summary
- Content license (documentation): https://developer.android.com/license
- SDK terms: https://developer.android.com/studio/terms
- AOSP licenses: https://source.android.com/docs/setup/about/licenses
- Brand guidelines: https://developer.android.com/distribute/marketing-tools/brand-guidelines

## Apple
- Agreements and guidelines: https://developer.apple.com/support/terms/
- Objective-C ↔ Swift interoperability: https://developer.apple.com/documentation/swift/importing-objective-c-into-swift
- Availability: https://developer.apple.com/documentation/swift/marking-api-availability-in-objective-c
- Xcode: https://developer.apple.com/xcode/

## React Native
- New Architecture: https://reactnative.dev/architecture/landing-page
- Turbo Native Modules: https://reactnative.dev/docs/turbo-native-modules-introduction
- Codegen: https://reactnative.dev/docs/the-new-architecture/what-is-codegen
- Pure C++ modules (JSI): https://reactnative.dev/docs/the-new-architecture/pure-cxx-modules

## GitHub
- GitHub Pages: https://docs.github.com/en/pages
- Custom Pages workflows: https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages
- Community health files: https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions
- Licensing a repository: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
