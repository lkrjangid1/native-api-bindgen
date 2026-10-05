#!/usr/bin/env bash
# Runs the platform-independent CI steps locally (the GitHub Actions
# workflows cannot run until the repository has a remote). Prints one
# PASS/FAIL line per step and exits non-zero if any step fails.
# Device suites are separate: tools/run_rn_device_tests.sh,
# tools/run_rn_ios_tests.sh and `flutter test integration_test` in examples.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
LOG="${TMPDIR:-/tmp}/nab_ci_local"
mkdir -p "$LOG"
failed=0
step() {
  local name="$1"; shift
  if "$@" >"$LOG/$name.log" 2>&1; then
    echo "PASS  $name"
  else
    echo "FAIL  $name (log: $LOG/$name.log)"
    failed=1
  fi
}
packages_test() {
  for d in packages/*/ runtimes/dart/native_api_runtime/; do
    [ -d "$d/test" ] || continue
    (cd "$d" && dart test) || return 1
  done
}
step pub-get dart pub get
step format dart format --output=none --set-exit-if-changed packages runtimes/dart tools
step analyze dart analyze --fatal-infos
step package-tests packages_test
step jvm-runtime-tests bash tools/run_jvm_runtime_tests.sh
step license-audit dart run native_api_bindgen audit-license
step website dart run tools/build_website.dart
step publish-dry-run bash tools/check_publish.sh
ui_plugin() {
  (cd runtimes/flutter/native_api_ui && flutter pub get >/dev/null && dart format --output=none --set-exit-if-changed lib && flutter analyze --fatal-infos)
}
step flutter-ui-plugin ui_plugin
if [ "${NAB_CI_NETWORK:-0}" = "1" ]; then
  step links dart run tools/check_links.dart README.md docs website/build
fi
exit $failed
