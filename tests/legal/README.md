# Legal guardrail fixtures

Restricted-artifact fixtures (Mach-O and fat binaries, class files, framework bundles, SDK header banners, `.tbd` stubs, copied documentation, foreign license headers) are **generated at test time** by `packages/native_api_core/test/legal_audit_test.dart`, so this repository never contains them and `audit-license` stays PASS.
