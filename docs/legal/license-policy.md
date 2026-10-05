# License policy

> **Not legal advice.** This document describes engineering policy. Organizations should perform their own legal review before commercial redistribution.

- Project source: Apache-2.0 (`LICENSE`). Chosen for its explicit patent grant; the repository owner may choose differently — this is a project/legal decision.
- The project license does **not** apply to platform SDKs, platform documentation, third-party dependencies, or bindings generated from platform SDKs.
- `native-api-bindgen audit-license` classifies every file and dependency as `PASS`, `WARN`, `BLOCK` or `REVIEW_REQUIRED`. Unknown licensing is never assumed permissive. Release workflows fail on `BLOCK`.
- Third-party license texts live in `licenses/`; summary in `THIRD_PARTY_NOTICES.md`.
