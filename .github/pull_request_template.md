## What and why

## Checklist
- [ ] Tests added/updated for any change to IR, type mapping, ownership, parser behaviour, generated API or license classification (parser / IR / golden / integration as applicable)
- [ ] `dart format`, `dart analyze --fatal-infos`, `dart test packages` pass
- [ ] Goldens regenerated deliberately (`UPDATE_GOLDENS=1`) and the diff reviewed
- [ ] `native-api-bindgen audit-license` is not BLOCK
- [ ] Platform facts come only from first-party sources (`docs/sources/official-sources.md`)
- [ ] No SDK files, copied documentation or machine paths committed
- [ ] CHANGELOG updated
