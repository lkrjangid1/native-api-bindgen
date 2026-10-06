# Releasing

Versions are shared by every package. Beta releases use `X.Y.Z-beta.N`.

1. Bump the version everywhere: `pubspec.yaml` files, `ProjectInfo` in `native_api_core`, `runtimes/jsi/package.json` and the runtime version strings, then regenerate goldens. Add a `## [X.Y.Z-beta.N] - <date>` section to `CHANGELOG.md`.
2. `bash tools/ci_local.sh` and `bash tools/check_publish.sh` are green.
3. **pub.dev** (manual): `dart pub publish` in dependency order:
   - `native_api_ir`
   - `native_api_core`
   - `native_api_generator`, `native_api_android`, `native_api_ios`
   - `native_api_flutter_android`, `native_api_flutter_ios`, `native_api_react_native_android`, `native_api_react_native_ios`
   - `native_api_cli` (package `native_api_bindgen`)
   - `native_api_runtime`
   - `native_api_ui` (with `flutter pub publish`)
4. **npm** (manual): `cd runtimes/jsi && npm publish --tag beta`. The account uses two-factor authentication, so run it from an interactive terminal and approve the staged publish on npmjs.com.
5. **GitHub Release and Homebrew**: push a tag `vX.Y.Z-beta.N`. `.github/workflows/release.yml` then:
   - runs `release-check`;
   - compiles `native-api-bindgen` with `dart compile exe` for `macos-arm64`, `macos-x64`, `linux-x64` and `linux-arm64`;
   - attaches the `.tar.gz` archives and their `.sha256` files to a GitHub Release (marked as a pre-release when the tag contains `-`);
   - writes `Formula/native-api-bindgen.rb` in [`lkrjangid1/homebrew-tap`](https://github.com/lkrjangid1/homebrew-tap) with `tools/homebrew_formula.py`.

## Homebrew tap: one-time setup

1. Create the public repository `lkrjangid1/homebrew-tap`, with a README and the default branch `main`.
2. Create a fine-grained personal access token limited to that repository, with **Contents: Read and write**.
3. In `lkrjangid1/native-api-bindgen` → Settings → Secrets and variables → Actions, add it as `HOMEBREW_TAP_TOKEN`.

Without the secret the release still succeeds; the `homebrew` job only logs a warning. To update the tap by hand, download the release's `.sha256` files into a directory and run:

```bash
python3 tools/homebrew_formula.py 0.1.0-beta.1 <dir> > Formula/native-api-bindgen.rb
```

Users install with:

```bash
brew install lkrjangid1/tap/native-api-bindgen
```
