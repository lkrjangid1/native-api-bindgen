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

rm -rf build/fixture_classes build/kotlin_stubs && mkdir -p build/fixture_classes build/kotlin_stubs
find_java() { python3 -c "import os,sys
for r,_,fs in os.walk(sys.argv[1]):
  for f in sorted(fs):
    if f.endswith('.java'): print(os.path.join(r,f))" "$1"; }
# shellcheck disable=SC2046
javac --release 17 -d build/kotlin_stubs $(find_java "$ROOT/fixtures/java/kotlin-stubs/src")
# shellcheck disable=SC2046
javac --release 17 -g -encoding UTF-8 -cp build/kotlin_stubs -d build/fixture_classes $(find_java "$ROOT/fixtures/java/basic/src")

cd "$ROOT"
# Fixture bindings are produced by the same extractor + emitter the CLI uses,
# with the synthetic fixture API list (see packages/native_api_android/lib/testing.dart).
dart run packages/native_api_flutter_android/tool/gen_fixtures.dart "$PKG/lib/src/generated"

# Kotlin fixtures (suspend functions): built with Gradle when available,
# run against kotlin-stdlib + kotlinx-coroutines from the Gradle cache.
KOTLIN_DIR="$ROOT/fixtures/kotlin/basic"
GRADLE="${NAB_GRADLE:-}"
[ -n "$GRADLE" ] || { [ -x "$KOTLIN_DIR/gradlew" ] && GRADLE="$KOTLIN_DIR/gradlew"; }
[ -n "$GRADLE" ] || GRADLE="$(command -v gradle || true)"
if [ -z "$GRADLE" ]; then
  GRADLE="$(ls -d "$HOME"/.gradle/wrapper/dists/gradle-9.6.0-bin/*/gradle-9.6.0/bin/gradle 2>/dev/null | head -1 || true)"
fi
export NAB_KOTLIN_CLASSPATH=""
if [ -n "$GRADLE" ] && { "$GRADLE" -p "$KOTLIN_DIR" jar --offline -q >/dev/null 2>&1 ||
    "$GRADLE" -p "$KOTLIN_DIR" jar -q; }; then
  KCP="$(python3 - "$HOME/.gradle/caches/modules-2/files-2.1" <<'PY'
import os, sys
root = sys.argv[1]
want = {
    "org.jetbrains.kotlin/kotlin-stdlib/2.4.20": "kotlin-stdlib-2.4.20.jar",
    "org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.10.2": "kotlinx-coroutines-core-jvm-1.10.2.jar",
}
found = []
for d, name in want.items():
    for r, _, fs in os.walk(os.path.join(root, d)):
        if name in fs:
            found.append(os.path.join(r, name))
            break
print(":".join(found) if len(found) == len(want) else "")
PY
)"
  if [ -n "$KCP" ]; then
    export NAB_KOTLIN_CLASSPATH="$KOTLIN_DIR/build/libs/kfixtures.jar:$KCP"
    dart run packages/native_api_flutter_android/tool/gen_kotlin_fixtures.dart "$PKG/lib/src/kotlin_generated"
  fi
fi
[ -n "$NAB_KOTLIN_CLASSPATH" ] || echo "Kotlin fixtures skipped (Gradle or Kotlin runtime jars unavailable)" >&2

cd "$PKG"
dart test "$@"
