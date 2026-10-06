# Legal release report (regenerate before each public release)

> Not legal advice. Items marked LEGAL_REVIEW_REQUIRED have not been reviewed by counsel. Last updated 2026-10-05 for 0.1.0-beta.1 (2026-10-06).

| Item | Status | Notes |
|---|---|---|
| Project license (Apache-2.0) | OK | `LICENSE`, `NOTICE`; every Dart package carries `LICENSE` |
| Third-party licenses | OK | dependencies resolved from pub/npm/CocoaPods/Maven at build time, none vendored; `audit-license` classifies pub dependencies; see `THIRD_PARTY_NOTICES.md` |
| Android SDK usage | LEGAL_REVIEW_REQUIRED | local `android.jar`/`api-versions.xml`/`annotations.zip` read in place; redistribution of generated bindings not reviewed |
| Apple SDK usage | LEGAL_REVIEW_REQUIRED | headers read in place by the Xcode toolchain's libclang; Swift symbol graphs kept in temporary directories; redistribution of generated bindings/adapters not reviewed (`docs/legal/apple.md`) |
| React Native integration | OK | documented New Architecture APIs; React Native not vendored (`docs/legal/react-native.md`) |
| Kotlin fixture / runtime libraries | OK | fixtures written for this project; kotlin-stdlib / kotlinx-coroutines (Apache-2.0) resolved by Gradle, not vendored |
| Documentation redistribution | OK | `links-only`; no platform documentation prose copied |
| Generated-code policy | OK | default `local-only`; generated directories git-ignored; `audit-license` warns on SDK-derived generated files and blocks SDK artifacts, Clang AST dumps and Swift symbol graphs |
| Trademark policy | OK | non-affiliation statements in README/NOTICE/website |
| Private API policy | OK | hidden/non-SDK Android APIs (E006) and `_`-prefixed Objective-C selectors (E005) never emitted |
| Publishing metadata | OPEN | `repository`/`homepage` fields need the real repository URL before `pub publish` |
| Known review items | LEGAL_REVIEW_REQUIRED | publishing generated Android/Apple bindings to pub.dev or npm |
