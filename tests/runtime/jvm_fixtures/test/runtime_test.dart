import 'dart:async';

import 'package:jni/jni.dart';
import 'package:jvm_fixture_runtime_tests/src/generated/bindings.dart';
import 'package:native_api_runtime/native_api_runtime.dart';
import 'package:test/test.dart';

import 'jvm.dart';

void main() {
  setUpAll(ensureJvm);

  JString js(String s) => s.toJString();

  group('calls', () {
    test('constructors and overloads dispatch to the right Java method', () {
      final o = OverloadedClass();
      expect(o.last()!.toDartString(), 'none');
      expect(OverloadedClass.new$int(7).last()!.toDartString(), 'ctor(int)=7');
      expect(
        OverloadedClass.new$String(js('x')).last()!.toDartString(),
        'ctor(String)=x',
      );
      expect(o.add(2, 3), 5);
      expect(o.add$long$long(1 << 40, 1), (1 << 40) + 1);
      expect(o.add$double$double(0.5, 0.25), 0.75);
      expect(o.add$String$String(js('a'), js('b'))!.toDartString(), 'ab');
      o.put(js('k'), 42);
      expect(o.last()!.toDartString(), 'int=42');
      o.put$String$boolean(js('k'), true);
      expect(o.last()!.toDartString(), 'boolean=true');
      o.put$String$byte(js('k'), -3);
      expect(o.last()!.toDartString(), 'byte=-3');
      o.put$String$char(js('k'), 'Z'.codeUnitAt(0));
      expect(o.last()!.toDartString(), 'char=Z');
      o.put$String$short(js('k'), 300);
      expect(o.last()!.toDartString(), 'short=300');
      o.put$String$float(js('k'), 1.5);
      expect(o.last()!.toDartString(), 'float=1.5');
      o.put$String$intArray(js('k'), JIntArray.of([1, 2, 3]));
      expect(o.last()!.toDartString(), 'int[]=3');
    });

    test('static methods, varargs and constants', () {
      final parts = JArray.of<JString?>(JString.type, [js('a'), js('b')]);
      expect(OverloadedClass.join(js('-'), parts)!.toDartString(), 'a-b');
      expect(AnnotatedClass.BIG, 9223372036854775807);
      expect(AnnotatedClass.HALF, 0.5);
      expect(
        AnnotatedClass.ACTION,
        r'com.example.ACTION "quoted" $dollar \slash',
      );
      expect(AnnotatedClass.UNICODE, 'café ☃');
      expect(AnnotatedClass.LETTER, 'x'.codeUnitAt(0));
      AnnotatedClass.counter = 41;
      expect(AnnotatedClass.counter, 41);
    });

    test('nullability: nullable returns and parameters', () {
      expect(NullableClass.find(js('missing')), isNull);
      final n = NullableClass.find(js('k'))!;
      expect(n.describe(null, js('v'), null).toDartString(), '<null>:v:null');
      expect(n.definitely.toDartString(), '');
      expect(n.maybe, isNull);
      n.maybe = js('set');
      expect(n.maybe!.toDartString(), 'set');
    });

    test('generics: Dart type parameters and java.util collections', () {
      final g = GenericClass<JString>(js('hello'));
      final JString? v = g.get();
      expect(v!.toDartString(), 'hello');
      g.set(js('bye'));
      expect(g.get()!.toDartString(), 'bye');

      final GenericClass<JString?> of = GenericClass.of(js('x'))!;
      expect(of.get()!.toDartString(), 'x');

      final JList<JString?> names = GenericClass.names(js('a'), js('bc'))!;
      expect(names.size(), 2);
      expect(names.get(1)!.toDartString(), 'bc');
      final JMap<JString?, JInteger?> lengths = GenericClass.lengths(names)!;
      expect(lengths.get(js('bc'))!.toDartInt(), 2);
      final JString? first = g.first<JString>(names);
      expect(first!.toDartString(), 'a');
    });

    test('multiple supertypes: inherited and redeclared members work', () {
      final d = DualImpl.create(3)!;
      expect(
        d.size(),
        3,
        reason: 'size() is inherited from two interfaces and redeclared',
      );
      final Sizable asSizable = d;
      expect(asSizable.size(), 3);
      final m = MultiParent();
      expect(
        m.name()!.toDartString(),
        '',
        reason: 'inherited from NestedClass',
      );
      expect(m.shouldContinue(), isTrue);
      expect(m.compareTo(m), 0);
    });

    test('nested types', () {
      final built = NestedClass_Builder().name(js('n'))!.build()!;
      expect(built.name()!.toDartString(), 'n');
    });
  });

  group('errors', () {
    test(
      'Java exceptions surface as NativeJavaException with class and message',
      () {
        expect(
          () => ThrowsClass.parse(js('nope')),
          throwsA(
            isA<NativeJavaException>()
                .having(
                  (e) => e.className,
                  'className',
                  'java.lang.NumberFormatException',
                )
                .having((e) => e.message, 'message', contains('nope'))
                .having(
                  (e) => e.isA('java.lang.IllegalArgumentException'),
                  'isA',
                  isTrue,
                ),
          ),
        );
        expect(
          () => ThrowsClass().read(),
          throwsA(
            isA<NativeJavaException>().having(
              (e) => e.className,
              'className',
              'java.io.IOException',
            ),
          ),
        );
        expect(ThrowsClass.parse(js('12')), 12);
      },
    );
  });

  group('callbacks', () {
    test('delivered on the calling thread with converted arguments', () {
      final events = <String>[];
      final cb = CallbackInterface.implement(
        $CallbackInterface(
          onEvent: (name, code) => events.add('${name.toDartString()}:$code'),
          shouldContinue: () => true,
          label: () => js('dart-label'),
        ),
      );
      final a = AsyncClass();
      a.load(js('abc'), cb);
      expect(events, ['abc:3']);
      expect(a.ask(cb), isTrue);
      expect(a.labelOf(cb)!.toDartString(), 'dart-label');
    });

    test('delivered from a foreign Java thread', () async {
      final done = Completer<String>();
      final cb = CallbackInterface.implement(
        $CallbackInterface(
          onEvent: (name, code) =>
              done.complete('${name.toDartString()}:$code'),
          shouldContinue: () => false,
          label: () => null,
          onEvent$async: true,
        ),
      );
      AsyncClass().loadOnThread(js('t'), cb);
      expect(await done.future.timeout(const Duration(seconds: 10)), 't:-1');
    });

    test('a throwing void callback is reported, not propagated', () async {
      final reported = <Object>[];
      NativeCallbacks.onError = (e, st, symbol) => reported.add(symbol);
      addTearDown(() => NativeCallbacks.onError = null);
      final errors = <Object>[];
      await runZonedGuarded(() async {
        final cb = CallbackInterface.implement(
          $CallbackInterface(
            onEvent: (name, code) => throw StateError('boom'),
            shouldContinue: () => true,
            label: () => null,
          ),
        );
        AsyncClass().load(js('x'), cb);
      }, (e, st) => errors.add(e));
      expect(reported, [
        'com.example.fixtures.CallbackInterface#onEvent(java.lang.String,int)',
      ]);
      expect(errors.single, isA<NativeCallbackError>());
    });

    test('a throwing non-void callback propagates to Java as an exception', () {
      final cb = CallbackInterface.implement(
        $CallbackInterface(
          onEvent: (name, code) {},
          shouldContinue: () => throw StateError('no answer'),
          label: () => null,
        ),
      );
      expect(() => AsyncClass().ask(cb), throwsA(isA<NativeJavaException>()));
    });
  });

  group('lifecycle', () {
    test('repeated create/release does not leak or crash', () {
      for (var i = 0; i < 10000; i++) {
        OverloadedClass.new$int(i).release();
      }
    });

    test('use after release throws; dispose is idempotent', () {
      final o = OverloadedClass();
      o.dispose();
      o.dispose();
      expect(o.isAlive, isFalse);
      expect(o.last, throwsA(isA<UseAfterReleaseError>()));
      expect(o.release, throwsA(isA<DoubleReleaseError>()));
    });

    test('availability guard throws before touching JNI on old devices', () {
      AndroidApi.debugOverrideFullVersion = 3000000;
      addTearDown(() => AndroidApi.debugOverrideFullVersion = null);
      expect(
        () => ApiLevelClass().since36minor(),
        throwsA(
          isA<NativeApiUnavailableException>().having(
            (e) => e.required,
            'required',
            '36.1',
          ),
        ),
      );
      expect(AndroidApi.isAtLeast(30), isTrue);
      expect(AndroidApi.isAtLeast(31), isFalse);
    });
  });
}
