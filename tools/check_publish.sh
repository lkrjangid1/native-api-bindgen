#!/usr/bin/env bash
# Runs `dart pub publish --dry-run` for every publishable Dart package and
# prints a one-line verdict per package. Publishing itself stays manual
# (see LEGAL_RELEASE_REPORT.md).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
status=0
for dir in "$ROOT"/packages/*/ "$ROOT"/runtimes/dart/native_api_runtime/; do
  [ -f "$dir/pubspec.yaml" ] || continue
  out="$(cd "$dir" && dart pub publish --dry-run 2>&1)"
  name="$(basename "$dir")"
  if printf '%s' "$out" | python3 -c "import sys; sys.exit(0 if 'missing a requirement' in sys.stdin.read() else 1)"; then
    echo "ERROR    $name"
    printf '%s\n' "$out" | python3 -c "import sys; t=sys.stdin.read(); i=t.find('Package validation found'); print(t[i:i+1500])"
    status=1
  else
    warnings="$(printf '%s' "$out" | python3 -c "
import re, sys
t = sys.stdin.read()
m = re.search(r'found the following (\d+ )?potential issues?', t)
print(m.group(0) if m else 'no warnings')
")"
    echo "OK       $name ($warnings)"
  fi
done
# npm: the React Native runtime package (dry run only).
if command -v npm >/dev/null 2>&1; then
  if out="$(cd "$ROOT/runtimes/jsi" && npm pack --dry-run 2>&1)"; then
    files="$(printf '%s' "$out" | python3 -c "import re,sys; m=re.search(r'total files:\s*(\d+)', sys.stdin.read()); print(m.group(1) if m else '?')")"
    echo "OK       native-api-bindgen-runtime (npm, $files files)"
  else
    echo "ERROR    native-api-bindgen-runtime (npm pack)"
    printf '%s\n' "$out" | tail -20
    status=1
  fi
fi
exit $status
