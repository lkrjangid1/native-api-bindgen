# Android legal / attribution policy

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

- **Inputs** come from the Android SDK Platform package installed by the developer through the official SDK Manager. Use of the SDK is governed by the Android SDK terms (https://developer.android.com/studio/terms). We never download, copy or commit SDK files; CI blocks `android.jar`/class-file blobs.
- **Documentation**: Android documentation content is licensed as described at https://developer.android.com/license (Apache 2.0 for code samples, CC BY 2.5 for most content). We do **not** copy documentation prose. Generated comments contain only metadata and links. If summaries are ever added (`documentationMode: summary`), they must be project-authored or carry the attribution the content license requires.
- **Generated bindings** contain API names, signatures, constant values and availability data derived from the locally installed SDK. Redistribution of such generated output is marked `LEGAL_REVIEW_REQUIRED`; default policy is `local-only`.
- **Trademarks**: "Android is a trademark of Google LLC." The Android robot is reproduced or modified from work created and shared by Google and used according to terms described in the Creative Commons 3.0 Attribution License — we do not currently use the robot or any Google logo. We do not imply endorsement.
- **Non-SDK interfaces**: never generated (E006); see https://developer.android.com/guide/app-compatibility/restrictions-non-sdk-interfaces.
