import 'package:jni/jni.dart';
import 'package:jvm_fixture_runtime_tests/src/generated/bindings.dart'
    show SuspendShaped;
import 'package:jvm_fixture_runtime_tests/src/kotlin_generated/bindings.dart';
import 'package:native_api_runtime/native_api_runtime.dart';
import 'package:test/test.dart';

import 'jvm.dart';

/// Kotlin `suspend` functions from fixtures/kotlin/basic, called through
/// generated bindings on a host JVM (package:jni PortContinuation).
void main() {
  if (kotlinClassPath.isEmpty) {
    test('kotlin', () {}, skip: 'Kotlin fixture jar / runtime not available');
    return;
  }
  setUpAll(ensureJvm);

  Greeter greeter(String name) => Greeter.create(name.toJString());

  test('regular function', () {
    expect(greeter('Ada').greet().toDartString(), 'Hello, Ada');
  });

  test('suspend function that suspends returns its value', () async {
    final r = await greeter('Ada').greetLater(20);
    expect(r!.toDartString(), 'Later, Ada');
  });

  test('suspend function that returns without suspending', () async {
    expect(await greeter('Grace').immediate(), 5);
  });

  test('suspend function returning Unit', () async {
    final sw = Stopwatch()..start();
    await greeter('x').pause(30);
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(25));
  });

  test('suspend function returning a Kotlin object', () async {
    final c = await greeter('Ada').child('!'.toJString());
    expect(c!.greet().toDartString(), 'Hello, Ada!');
  });

  test('exception after suspension surfaces as NativeJavaException', () async {
    await expectLater(
      greeter('x').failLater('boom'.toJString()),
      throwsA(
        isA<NativeJavaException>()
            .having(
              (e) => e.className,
              'className',
              'java.lang.IllegalStateException',
            )
            .having((e) => e.message, 'message', contains('boom')),
      ),
    );
  });

  test('many concurrent suspend calls complete independently', () async {
    final g = greeter('n');
    final results = await Future.wait([
      for (var i = 0; i < 50; i++) g.greetLater(i % 7),
    ]);
    expect(results.map((r) => r!.toDartString()).toSet(), {'Later, n'});
  });

  test(
    'Java method shaped like a suspend function (returns directly)',
    () async {
      final s = SuspendShaped();
      expect((await s.load('k'.toJString()))!.toDartString(), 'loaded:k');
      expect(await s.count(), 3);
    },
  );
}
