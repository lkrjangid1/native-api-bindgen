# Legal release report (template — regenerate before each public release)

> Not legal advice. Items marked LEGAL_REVIEW_REQUIRED have not been reviewed by counsel.

| Item | Status | Notes |
|---|---|---|
| Project license (Apache-2.0) | OK | `LICENSE`, `NOTICE` present |
| Third-party licenses | OK | pub dependencies only, none vendored; see `THIRD_PARTY_NOTICES.md` |
| Android source/material usage | LEGAL_REVIEW_REQUIRED | Local SDK consumption only; redistribution of generated bindings not yet reviewed |
| Apple SDK usage model | N/A (not implemented) | Policy in `docs/legal/apple.md` |
| Documentation redistribution | OK | `links-only`; no documentation prose copied |
| Generated-code policy | OK | default `local-only`; generated dirs git-ignored |
| Trademark policy | OK | non-affiliation statements in README/NOTICE |
| Private API policy | OK | hidden/non-SDK never emitted (E006) |
| Known review items | LEGAL_REVIEW_REQUIRED | publishing generated Android bindings to pub.dev |
