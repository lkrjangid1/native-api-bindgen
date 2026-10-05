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
exit $status
