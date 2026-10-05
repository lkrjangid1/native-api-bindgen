# Contributing

Thanks for helping. Please read this before opening a pull request.

## Ground rules

1. **First-party sources only** for platform facts. A generated symbol must be traceable to a local SDK artifact or an official reference listed in `docs/sources/official-sources.md`. Blogs, Stack Overflow and unofficial mirrors are not acceptable sources of API metadata.
2. **Never commit SDK files** (android.jar, Apple headers, frameworks). `native-api-bindgen audit-license` runs in CI and blocks this.
3. **No silent drops.** If the generator cannot represent something, emit a diagnostic with a stable code (`docs/error-codes.md`) and add a test proving it.
4. **Determinism.** Same SDK + generator version + configuration must produce byte-identical output. No timestamps, no hash-map iteration order.
5. **Tests with every change** to the IR, type mapping, parser behaviour, ownership model, generated API or license classification (parser test, IR test, golden test, integration test as applicable).

## Workflow

```bash
dart pub get
dart format .
dart analyze --fatal-infos
dart test packages/native_api_ir packages/native_api_core packages/native_api_android \
          packages/native_api_generator packages/native_api_flutter_android packages/native_api_cli
dart run native_api_bindgen:native-api-bindgen audit-license
```

Update goldens deliberately with `UPDATE_GOLDENS=1 dart test packages/native_api_flutter_android` and review the diff.

## Commits

Conventional commits, small and focused: `feat(ir): …`, `fix(android): …`, `test(flutter): …`, `docs(legal): …`.

## License of contributions

Contributions are accepted under Apache-2.0 (inbound = outbound). Do not contribute material you are not entitled to license, including copied platform documentation.
