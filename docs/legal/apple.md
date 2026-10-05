# Apple SDK policy

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

Apple SDK support is **not implemented yet**. This policy applies from the first line of Apple-related code.

We will **not**:
- vendor Apple SDKs or commit any Apple SDK file (headers, `.tbd`, `.framework`, `.xcframework`, binaries) to Git;
- publish Apple framework binaries copied from Xcode;
- copy Apple documentation bodies into generated packages or scrape and republish Apple documentation;
- expose private Apple APIs as supported (E005), or provide guidance on App Store policy evasion.

We **may**, subject to the Xcode and Apple SDKs Agreement (https://developer.apple.com/support/terms/), generate bindings on the developer's own machine from the SDK installed with their Xcode. Generated output will contain declarations, binding code, symbol names, availability metadata, developer-authored text and links to developer.apple.com.

Tests use **synthetic** Objective-C headers written for this project, never copies of SDK headers. Automated checks (`audit-license`) detect Mach-O binaries, framework bundles, Apple copyright banners typical of SDK headers, and Xcode SDK paths, and block them.

Apple, iOS, iPadOS, macOS, Xcode, Objective-C and Swift are trademarks of Apple Inc. This project is not affiliated with or endorsed by Apple.
