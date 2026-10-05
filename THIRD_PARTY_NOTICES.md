# Third-party notices

This file lists third-party material that the project depends on or interacts with.
It is maintained together with `native-api-bindgen audit-license`, which produces a
machine-readable report (`--json`). It is an engineering record, not legal advice.

## Redistributed inside this repository

None. The repository contains no third-party source, binaries or SDK files.
`audit-license` fails (BLOCK) if SDK artifacts are committed.

## Runtime / build dependencies (resolved via pub.dev, not vendored)

| Package | Publisher | License | Used by | Redistributed? |
|---|---|---|---|---|
| `jni` | dart.dev (tools.dart.dev) | BSD-3-Clause | generated Flutter Android bindings, runtime | No (pub dependency) |
| `jni_flutter` | dart.dev | BSD-3-Clause | Flutter example (Context/Activity access) | No |
| `archive` | pub.dev community | MIT | reading `android.jar` / `annotations.zip` | No |
| `xml` | pub.dev community | MIT | `api-versions.xml`, `annotations.zip` | No |
| `args`, `path`, `yaml`, `collection`, `crypto`, `meta` | dart.dev | BSD-3-Clause | CLI / core | No |
| `test`, `lints` | dart.dev | BSD-3-Clause | development only | No |

Exact versions are pinned in `pubspec.lock` files of applications; `audit-license --json`
lists the resolved set.

## Inputs consumed locally, never redistributed

| Input | Owner | Terms | Handling |
|---|---|---|---|
| Android SDK Platform (`android.jar`, `data/api-versions.xml`, `data/annotations.zip`) | Google LLC / AOSP | Android SDK License Agreement; AOSP components under Apache-2.0 | Read locally. Only symbol names, signatures, constant values and availability metadata enter generated output. `LEGAL_REVIEW_REQUIRED` for redistribution of generated bindings — default `distribution.generatedArtifacts: local-only`. |
| Xcode / Apple SDKs | Apple Inc. | Xcode and Apple SDKs Agreement | Not used yet. Will be read locally only; never redistributed. |
