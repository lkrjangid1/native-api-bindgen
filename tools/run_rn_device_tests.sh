#!/usr/bin/env bash
# Builds the React Native example (release, bundled JS), installs it on a
# connected device/emulator, launches it, and checks the NAB_TEST lines the
# app's self-test suite writes to logcat. Fails on any FAIL or on timeout.
# With several devices attached, select one with ANDROID_SERIAL=<serial>.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/examples/react-native/slice"
if [ -z "${ANDROID_HOME:-}" ]; then
  for d in "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [ -n "$d" ] && [ -d "$d/platforms" ]; then export ANDROID_HOME="$d"; break; fi
  done
fi
ADB="$ANDROID_HOME/platform-tools/adb"
PKG=com.nabrnslice
TIMEOUT="${NAB_TEST_TIMEOUT:-180}"

cd "$ROOT"
dart run native_api_bindgen --quiet --project examples/react-native/slice generate react-native
cd "$APP"
[ -d node_modules ] || npm install
npx tsc --noEmit
(cd android && ./gradlew assembleRelease --console=plain -q)
"$ADB" install -r android/app/build/outputs/apk/release/app-release.apk >/dev/null
"$ADB" logcat -c
"$ADB" shell am force-stop "$PKG"
"$ADB" shell am start -n "$PKG/.MainActivity" >/dev/null

deadline=$(( $(date +%s) + TIMEOUT ))
while true; do
  out="$("$ADB" logcat -d -s ReactNativeJS:V | python3 -c "import sys; print(''.join(l for l in sys.stdin if 'NAB_TEST' in l))")"
  if printf '%s' "$out" | python3 -c "import sys; sys.exit(0 if 'NAB_TEST DONE' in sys.stdin.read() else 1)"; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf '%s\n' "$out"
    echo "Timed out waiting for NAB_TEST DONE" >&2
    "$ADB" logcat -d | python3 -c "import sys; L=sys.stdin.read().split('\n'); print('\n'.join(l for l in L if 'AndroidRuntime' in l or 'nabrnslice' in l or 'FATAL' in l or 'libc' in l)[-4000:])" >&2
    exit 1
  fi
  sleep 2
done
printf '%s\n' "$out" | python3 -c "
import re, sys
text = sys.stdin.read()
for line in text.split('\n'):
    m = re.search(r'NAB_TEST (.*)', line)
    if m: print(m.group(1))
done = re.search(r'NAB_TEST DONE pass=(\d+) fail=(\d+)', text)
sys.exit(0 if done and done.group(2) == '0' else 1)
"
