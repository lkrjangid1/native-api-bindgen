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
    expect(r.toDartString(), 'Later, Ada');
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
    expect(c.greet().toDartString(), 'Hello, Ada!');
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
    expect(results.map((r) => r.toDartString()).toSet(), {'Later, n'});
  });

  group('kotlin.Metadata', () {
    test('nullable suspend result stays nullable', () async {
      final g = greeter('Ada');
      expect((await g.maybe(true))?.toDartString(), 'yes, Ada');
      expect(await g.maybe(false), isNull);
    });

    test('Kotlin properties are bean properties', () {
      final g = greeter('Ada');
      expect(g.nickname, isNull);
      g.nickname = 'Countess'.toJString();
      expect(g.getNickname()!.toDartString(), 'Countess');
      expect(g.nameLength, 3);
      expect(g.loud, isFalse);
      g.loud = true;
      expect(g.isLoud(), isTrue);
    });

    test('default arguments must be passed explicitly', () {
      expect(
        greeter(
          'x',
        ).repeat('ab'.toJString(), 3, '-'.toJString()).toDartString(),
        'ab-ab-ab',
      );
    });
  });

  group('Flow -> Stream', () {
    test('collects every value, then closes', () async {
      expect(await greeter('x').countTo(5).toList(), [1, 2, 3, 4, 5]);
    });

    test('nullable elements', () async {
      final words = await greeter('x').words().toList();
      expect(words.map((w) => w?.toDartString()), ['a', null, 'c']);
    });

    test('a Kotlin exception is a stream error after earlier values', () async {
      final values = <String>[];
      Object? error;
      await greeter('x')
          .failing('bad'.toJString())
          .handleError((Object e) => error = e)
          .forEach((v) => values.add(v.toDartString()));
      expect(values, ['first']);
      expect(
        error,
        isA<NativeJavaException>().having(
          (e) => e.message,
          'message',
          contains('bad'),
        ),
      );
    });

    test('cancelling the subscription stops an endless flow', () async {
      final first = await greeter('x').ticks().take(3).toList();
      expect(first, [0, 1, 2]);
    });

    test('not collected until listened to', () async {
      final s = greeter('x').countTo(2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await s.toList(), [1, 2]);
    });
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
