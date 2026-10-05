import 'dart:io';

import 'package:jni/jni.dart';

/// Kotlin classpath (fixture jar, kotlin-stdlib, kotlinx-coroutines) from
/// tools/run_jvm_runtime_tests.sh, or empty when Kotlin is unavailable.
List<String> get kotlinClassPath {
  final cp = Platform.environment['NAB_KOTLIN_CLASSPATH'] ?? '';
  return cp.isEmpty ? const [] : cp.split(':');
}

/// Starts the JVM once per process (all test files share it).
void ensureJvm() {
  if (!File('build/jni_libs/jni.jar').existsSync()) {
    throw StateError(
      'Run tools/run_jvm_runtime_tests.sh (missing build/jni_libs).',
    );
  }
  Jni.spawnIfNotExists(
    dylibDir: 'build/jni_libs',
    classPath: [
      'build/fixture_classes',
      'build/jni_libs/jni.jar',
      ...kotlinClassPath,
    ],
  );
}
