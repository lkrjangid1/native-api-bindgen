#!/usr/bin/env bash
# Runs generated fixture bindings against a host JVM via package:jni.
# Requires: Dart SDK, JDK (javac), CMake (Android SDK's cmake/<ver>/bin is used
# if cmake is not on PATH). Builds package:jni's native helper once.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/tests/runtime/jvm_fixtures"

if ! command -v cmake >/dev/null 2>&1; then
  for d in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$HOME/Library/Android/sdk" "$HOME/Android/Sdk"; do
    if [ -n "$d" ] && [ -d "$d/cmake" ]; then
      CM="$(ls -d "$d"/cmake/*/bin | sort -V | tail -1)"
      export PATH="$CM:$PATH"
      break
    fi
  done
fi
if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_HOME="$(cd "$(dirname "$(readlink -f "$(command -v javac)")")/.." && pwd)"
  export JAVA_HOME
fi

cd "$PKG"
dart pub get >/dev/null
if [ ! -f build/jni_libs/libdartjni.dylib ] && [ ! -f build/jni_libs/libdartjni.so ]; then
  J="$JAVA_HOME"
  INC2="$J/include/darwin"; [ -d "$INC2" ] || INC2="$J/include/linux"
  LIBEXT=dylib; [ "$(uname)" = "Darwin" ] || LIBEXT=so
  dart run jni:setup --cmake-args "-DJAVA_AWT_INCLUDE_PATH=$J/include -DJAVA_INCLUDE_PATH=$J/include -DJAVA_INCLUDE_PATH2=$INC2 -DJAVA_AWT_LIBRARY=$J/lib/libjawt.$LIBEXT -DJAVA_JVM_LIBRARY=$J/lib/server/libjvm.$LIBEXT"
fi

rm -rf build/fixture_classes && mkdir -p build/fixture_classes
find_java() { python3 -c "import os,sys
for r,_,fs in os.walk(sys.argv[1]):
  for f in sorted(fs):
    if f.endswith('.java'): print(os.path.join(r,f))" "$1"; }
# shellcheck disable=SC2046
javac --release 17 -g -encoding UTF-8 -d build/fixture_classes $(find_java "$ROOT/fixtures/java/basic/src")

cd "$ROOT"
# Fixture bindings are produced by the same extractor + emitter the CLI uses,
# with the synthetic fixture API list (see packages/native_api_android/lib/testing.dart).
dart run packages/native_api_flutter_android/tool/gen_fixtures.dart "$PKG/lib/src/generated"

cd "$PKG"
dart test "$@"
