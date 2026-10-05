import 'dart:async';

import 'package:android_slice/src/generated/bindings.dart';
import 'package:android_slice/src/slice.dart';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart'
    show Center, Directionality, SizedBox, TextDirection;
import 'package:integration_test/integration_test.dart';
import 'package:native_api_ui/native_api_ui.dart';
import 'package:native_api_runtime/native_api_runtime.dart' as rt;
import 'package:jni/jni.dart';
import 'package:native_api_runtime/native_api_runtime.dart';

/// End-to-end tests of generated bindings against the real Android framework
/// on a device or emulator (TRD §45, §113).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  JString js(String s) => s.toJString();

  test('Context: package name and API level', () {
    expect(Slice.packageName(), 'dev.nativeapibindgen.examples.android_slice');
    expect(AndroidApi.sdkInt, greaterThanOrEqualTo(24));
  });

  test('Intent + Uri: constructor overload, constants, nullable setter', () {
    final r = Slice.viewIntent('https://example.com/path?q=1');
    expect(r.action, 'android.intent.action.VIEW');
    expect(Intent.ACTION_VIEW, 'android.intent.action.VIEW');
    expect(r.data, 'https://example.com/path?q=1');

    final intent = Intent();
    expect(intent.getData(), isNull);
    intent.setData(Uri.parse(js('content://x/y')));
    expect(intent.getData().toString(), 'content://x/y');
    intent.setData(null); // @Nullable parameter
    expect(intent.getData(), isNull);
    expect(intent.setAction(js('a.b.C')).getAction()!.toDartString(), 'a.b.C');
  });

  test('Typed @IntDef/@StringDef constants pass as raw values', () {
    final intent = Intent();
    final flags =
        Intent$Flag.FLAG_ACTIVITY_NEW_TASK |
        Intent$Flag.FLAG_ACTIVITY_CLEAR_TOP;
    intent.setFlags(flags);
    expect(
      intent.getFlags(),
      Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP,
    );
    expect(flags.has(Intent$Flag.FLAG_ACTIVITY_NEW_TASK), isTrue);
    expect(flags.has(Intent$Flag.FLAG_ACTIVITY_CLEAR_TASK), isFalse);
    expect(Context$Service.ALARM_SERVICE, Context.ALARM_SERVICE);
  });

  test('byte[] and direct ByteBuffer transfers', () {
    final data = Uint8List.fromList([1, 2, 255, 0, 128]);
    final a = rt.byteArrayOf(data);
    final copy = Arrays.copyOf(a, 3);
    expect(rt.bytesOf(copy), [1, 2, 255]);
    final buffer = rt.directBufferOf(data);
    expect(buffer.isDirect, isTrue);
    expect(buffer.asUint8List(), data);
  });

  testWidgets('native UI: a TextView created through bindings is shown', (
    tester,
  ) async {
    final label = TextView(Slice.appContext)
      ..setText$CharSequence('Hello native'.toJString());
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 240,
            height: 80,
            child: NativeView.android(view: label),
          ),
        ),
      ),
    );
    for (var i = 0; i < 50 && !label.isAttachedToWindow(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NativeView), findsOneWidget);
    expect(label.isAttachedToWindow(), isTrue);
    expect(label.getText().toString(), 'Hello native');
    expect(label.getWidth(), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  test('Bean properties delegate to the native getters', () {
    final uri = Uri.parse(js('https://example.com/p?q=1'))!;
    expect(uri.scheme!.toDartString(), 'https');
    expect(uri.host!.toDartString(), 'example.com');
    expect(uri.scheme!.toDartString(), uri.getScheme()!.toDartString());
    final intent = Intent();
    expect(intent.data, isNull);
    intent.setData(uri);
    expect(intent.data.toString(), 'https://example.com/p?q=1');
  });

  test('Intent.putExtra overloads reach distinct Java methods', () {
    final intent = Intent();
    intent.putExtra(js('i'), 7); // primary overload: putExtra(String, int)
    intent.putExtra$String$boolean(js('b'), true);
    intent.putExtra$String$String(js('s'), js('text'));
    intent.putExtra$String$long(js('l'), 1 << 40);
    expect(intent.getIntExtra(js('i'), -1), 7);
    expect(intent.getBooleanExtra(js('b'), false), isTrue);
    expect(intent.getStringExtra(js('s'))!.toDartString(), 'text');
    expect(intent.getLongExtra(js('l'), 0), 1 << 40);
    expect(intent.getIntExtra(js('missing'), -1), -1);
  });

  test('Bundle (inherits BaseBundle): put/get, null for missing keys', () {
    expect(Slice.bundleRoundTrip(), ('hello from Dart', null));
    final b = Bundle();
    b.putInt(js('n'), 41);
    expect(b.getInt(js('n')), 41);
    expect(b.containsKey(js('n')), isTrue);
    expect(b.size(), 1);
  });

  test('Uri static factories and getters', () {
    // withAppendedPath appends an *encoded* path segment verbatim (Android
    // semantics), so the space is not re-encoded.
    final uri = Uri.withAppendedPath(
      Uri.parse(js('https://example.com')),
      js('a%20b'),
    )!;
    expect(uri.getEncodedPath()!.toDartString(), '/a%20b');
    expect(uri.getPath()!.toDartString(), '/a b');
    expect(uri.getScheme()!.toDartString(), 'https');
    final opaque = Uri.fromParts(js('mailto'), js('dev@example.com'), null)!;
    expect(opaque.isOpaque(), isTrue);
    expect(opaque.getSchemeSpecificPart()!.toDartString(), 'dev@example.com');
  });

  test('Activity: inherited Context methods are callable on Activity', () {
    expect(Slice.activityClassName(), 'MainActivity');
  });

  test(
    'Handler.post(Runnable): Dart callback runs on the main Looper',
    () async {
      final result = await Slice.postToMainLooper().timeout(
        const Duration(seconds: 10),
      );
      expect(result, 'Runnable ran (main looper: true)');
    },
  );

  test('Handler.Callback: Dart handles a Message sent from Java', () async {
    final received = Completer<int>();
    final callback = Handler_Callback.implement(
      $Handler_Callback(
        handleMessage: (msg) {
          received.complete(msg.what);
          return true;
        },
      ),
    );
    final handler = Handler.new$Looper$Callback(
      Looper.getMainLooper()!,
      callback,
    );
    expect(handler.sendEmptyMessage(42), isTrue);
    expect(await received.future.timeout(const Duration(seconds: 10)), 42);
  });

  test(
    'a throwing void callback is reported and does not crash the app',
    () async {
      final reported = Completer<String>();
      NativeCallbacks.onError = (e, st, symbol) => reported.complete(symbol);
      addTearDown(() => NativeCallbacks.onError = null);
      final errors = <Object>[];
      runZonedGuarded(() {
        final handler = Handler.new$Looper(Looper.getMainLooper()!);
        handler.post(
          Runnable.implement(
            $Runnable(run: () => throw StateError('boom'), run$async: true),
          ),
        );
      }, (e, st) => errors.add(e));
      expect(
        await reported.future.timeout(const Duration(seconds: 10)),
        'java.lang.Runnable#run()',
      );
      // The app (and the main Looper) keep working afterwards.
      expect(
        await Slice.postToMainLooper().timeout(const Duration(seconds: 10)),
        contains('main looper: true'),
      );
    },
  );

  test('Java exceptions surface as NativeJavaException', () {
    final b = Bundle();
    // Bundle.getParcelable on a String value logs a warning and returns null,
    // so use an API that throws: Intent.parseUri with a malformed URI.
    expect(
      () => Intent.parseUri(js('#Intent;nope'), 0),
      throwsA(
        isA<NativeJavaException>().having(
          (e) => e.className,
          'className',
          'java.net.URISyntaxException',
        ),
      ),
    );
    b.release();
  });

  test('availability guard fails safely for APIs newer than the device', () {
    // Pretend the device runs API 24; Intent.removeLaunchSecurityProtection
    // was added in API 36, so the guard must throw before JNI is touched.
    AndroidApi.debugOverrideFullVersion = 2400000;
    addTearDown(() => AndroidApi.debugOverrideFullVersion = null);
    expect(
      () => Intent().removeLaunchSecurityProtection(),
      throwsA(
        isA<NativeApiUnavailableException>().having(
          (e) => e.required,
          'required',
          '36',
        ),
      ),
    );
  });

  test(
    'lifecycle: 10k create/release, use-after-release, idempotent dispose',
    () {
      for (var i = 0; i < 10000; i++) {
        Bundle().release();
      }
      final b = Bundle();
      b.dispose();
      b.dispose();
      expect(b.isAlive, isFalse);
      expect(() => b.size(), throwsA(isA<UseAfterReleaseError>()));
    },
  );

  group('Kotlin suspend functions (library jar)', () {
    test('a suspending call completes the Future', () async {
      final g = Greeter.create(js('Ada'));
      expect((await g.greetLater(20)).toDartString(), 'Later, Ada');
      expect(await g.maybe(false), isNull);
      expect(await g.immediate(), 3);
      await g.pause(10);
    });

    test('a Kotlin Flow is collected into a Stream', () async {
      final g = Greeter.create(js('Ada'));
      expect(await g.countTo(4).toList(), [1, 2, 3, 4]);
      expect(await g.ticks().take(3).toList(), [0, 1, 2]);
      expect((await g.words().toList()).map((w) => w?.toDartString()), [
        'a',
        null,
        'c',
      ]);
    });

    test(
      'a Kotlin exception fails the Future with NativeJavaException',
      () async {
        await expectLater(
          Greeter.create(js('x')).failLater(js('boom')),
          throwsA(
            isA<NativeJavaException>().having(
              (e) => e.className,
              'className',
              'java.lang.IllegalStateException',
            ),
          ),
        );
      },
    );
  });
}
