# Apple SDK policy

<!-- description: How native-api-bindgen reads Apple SDK headers in place with Xcode, what it never copies, and what the Xcode and Apple SDKs Agreement allows. -->

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

## Mechanism (as implemented)

- The SDK is located with `xcode-select`/`xcrun`; headers are read **in place** from the locally installed Xcode by the Xcode toolchain's own libclang. Nothing from the SDK is copied into the repository, the generator, or published packages.
- The extractor keeps declarations, symbol names, types, nullability and availability metadata only. Header comments and Apple documentation are **not** copied; generated docs contain the Objective-C signature, availability lines and (optionally) links to developer.apple.com.
- Generated Dart output (`apple/*.dart`) carries a `Source SDK: Apple SDK <version>` header and is **local-only by default** (`distribution.generatedArtifacts: local-only`). `audit-license` reports such files as `generated-sdk-binding` (WARN, LEGAL_REVIEW_REQUIRED before redistribution).
- No absolute SDK paths are embedded in IR or generated code (tested).
- Clang AST dumps, precompiled headers and module caches (`.pch`, `.pcm`, `.ast`, JSON AST) are never written to the repository; `audit-license` blocks them (`clang-ast-dump`) and `.gitignore` excludes them.

We will **not**:
- vendor Apple SDKs or commit any Apple SDK file (headers, `.tbd`, `.framework`, `.xcframework`, binaries) to Git;
- publish Apple framework binaries copied from Xcode;
- copy Apple documentation bodies into generated packages or scrape and republish Apple documentation;
- expose private Apple APIs as supported (E005), or provide guidance on App Store policy evasion.

We **may**, subject to the Xcode and Apple SDKs Agreement (https://developer.apple.com/support/terms/), generate bindings on the developer's own machine from the SDK installed with their Xcode. Generated output will contain declarations, binding code, symbol names, availability metadata, developer-authored text and links to developer.apple.com.

Tests use **synthetic** Objective-C headers written for this project, never copies of SDK headers. Automated checks (`audit-license`) detect Mach-O binaries, framework bundles, Apple copyright banners typical of SDK headers, and Xcode SDK paths, and block them.

Apple, iOS, iPadOS, macOS, Xcode, Objective-C and Swift are trademarks of Apple Inc. This project is not affiliated with or endorsed by Apple.
