#!/usr/bin/env bash
# Builds the React Native example for the iOS simulator (Release, bundled
# JS), installs and launches it, and checks the NAB_TEST lines the app's
# self-test suite writes to the unified log. Fails on any FAIL or timeout.
# Select a simulator with NAB_IOS_SIMULATOR=<udid> (default: first available
# iPhone on the newest installed iOS runtime).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/examples/react-native/slice"
BUNDLE_ID="org.reactjs.native.example.NabRnSlice"
TIMEOUT="${NAB_TEST_TIMEOUT:-180}"

UDID="${NAB_IOS_SIMULATOR:-}"
if [ -z "$UDID" ]; then
  UDID="$(xcrun simctl list devices available -j | python3 -c "
import json, sys
d = json.load(sys.stdin)['devices']
print(next(x['udid'] for k, v in sorted(d.items(), reverse=True) if 'iOS' in k for x in v if x['name'].startswith('iPhone')))
")"
fi

cd "$ROOT"
dart run native_api_bindgen --quiet --project examples/react-native/slice generate react-native
cd "$APP"
[ -d node_modules ] || npm install
npx tsc --noEmit
[ -d ios/Pods ] || (cd ios && pod install)
xcodebuild -workspace ios/NabRnSlice.xcworkspace -scheme NabRnSlice -configuration Release \
  -sdk iphonesimulator -destination "id=$UDID" -derivedDataPath ios/build \
  CODE_SIGNING_ALLOWED=NO -quiet
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" ios/build/Build/Products/Release-iphonesimulator/NabRnSlice.app
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
start="$(date '+%Y-%m-%d %H:%M:%S')"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

deadline=$(( $(date +%s) + TIMEOUT ))
while true; do
  out="$(xcrun simctl spawn "$UDID" log show --start "$start" --style compact \
    --predicate 'eventMessage CONTAINS "NAB_TEST"' 2>/dev/null || true)"
  if printf '%s' "$out" | python3 -c "import sys; sys.exit(0 if 'NAB_TEST DONE' in sys.stdin.read() else 1)"; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf '%s\n' "$out"
    echo "Timed out waiting for NAB_TEST DONE" >&2
    xcrun simctl spawn "$UDID" log show --start "$start" --style compact \
      --predicate 'process == "NabRnSlice"' 2>/dev/null | tail -60 >&2 || true
    exit 1
  fi
  sleep 2
done
printf '%s\n' "$out" | python3 -c "
import re, sys
text = sys.stdin.read()
seen = set()
for line in text.split('\n'):
    m = re.search(r'NAB_TEST (.*)', line)
    if m and m.group(1) not in seen:
        seen.add(m.group(1)); print(m.group(1))
done = re.search(r'NAB_TEST DONE pass=(\d+) fail=(\d+)', text)
sys.exit(0 if done and done.group(2) == '0' else 1)
"
