import 'dart:async';
import 'dart:convert';

import 'package:android_slice/src/generated/bindings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jni/jni.dart';
import 'package:native_api_runtime/native_api_runtime.dart' as rt;

/// Micro-benchmarks (TRD §35): generated JNI bindings vs. a hand-written
/// MethodChannel doing the same work. Run in profile mode:
///   flutter drive --profile --driver=test_driver/integration_test.dart \
///     --target=integration_test/bench_test.dart -d DEVICE
/// Prints one `NAB_BENCH {json}` line. Numbers depend on the device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  double nsPerCall(int n, void Function() f) {
    for (var i = 0; i < n ~/ 10; i++) {
      f();
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      f();
    }
    return sw.elapsedMicroseconds * 1000 / n;
  }

  Future<double> usPerAsyncCall(int n, Future<void> Function() f) async {
    for (var i = 0; i < n ~/ 10; i++) {
      await f();
    }
    final sw = Stopwatch()..start();
    for (var i = 0; i < n; i++) {
      await f();
    }
    return sw.elapsedMicroseconds / n;
  }

  double median(List<int> xs) {
    xs.sort();
    return xs[xs.length ~/ 2].toDouble();
  }

  test('benchmarks', () async {
    final results = <String, num>{};
    final bundle = Bundle();
    results['jni_instance_call_int_ns'] = nsPerCall(200000, bundle.size);
    final uriText = 'https://example.com/path?q=1'.toJString();
    results['jni_static_call_object_ns'] = nsPerCall(50000, () {
      Uri.parse(uriText)?.release();
    });
    results['jni_string_roundtrip_ns'] = nsPerCall(20000, () {
      final u = Uri.parse('https://example.com/path?q=1'.toJString());
      u?.toString();
      u?.release();
    });

    // Byte transfers (TRD §36): Dart -> byte[] -> Arrays.copyOf -> Dart, and
    // the same through a MethodChannel; direct ByteBuffer view (no copy).
    double msPer(int n, void Function() f) {
      f();
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        f();
      }
      return sw.elapsedMicroseconds / 1000 / n;
    }

    const bytesChannel = MethodChannel('nab/bench');
    for (final (label, size) in [('1mb', 1 << 20), ('16mb', 16 << 20)]) {
      final data = Uint8List(size)..fillRange(0, size, 7);
      results['jni_bytes_roundtrip_${label}_ms'] = msPer(10, () {
        final a = rt.byteArrayOf(data);
        final copy = Arrays.copyOf(a, size);
        final back = rt.bytesOf(copy);
        if (back.length != size) throw StateError('size');
        a.release();
        copy.release();
      });
      final channelMs = <int>[];
      for (var i = 0; i < 10; i++) {
        final sw = Stopwatch()..start();
        final back = await bytesChannel.invokeMethod<Uint8List>(
          'copyBytes',
          data,
        );
        if (back!.length != size) throw StateError('size');
        channelMs.add(sw.elapsedMicroseconds);
      }
      results['methodchannel_bytes_roundtrip_${label}_ms'] =
          median(channelMs) / 1000;
      results['jni_direct_buffer_fill_${label}_ms'] = msPer(10, () {
        final b = rt.directBufferOf(data);
        if (b.asUint8List().length != size) throw StateError('size');
        b.release();
      });
    }

    const channel = MethodChannel('nab/bench');
    results['methodchannel_noop_us'] = await usPerAsyncCall(
      5000,
      () => channel.invokeMethod<void>('noop'),
    );
    results['methodchannel_bundle_size_us'] = await usPerAsyncCall(
      5000,
      () => channel.invokeMethod<int>('bundleSize'),
    );
    results['methodchannel_string_roundtrip_us'] = await usPerAsyncCall(
      5000,
      () => channel.invokeMethod<String>(
        'parseUri',
        'https://example.com/path?q=1',
      ),
    );

    // Java -> Dart callback latency: Handler.post on the main Looper.
    final handler = Handler.new$Looper(Looper.getMainLooper()!);
    final samples = <int>[];
    for (var i = 0; i < 300; i++) {
      final done = Completer<void>();
      final sw = Stopwatch()..start();
      final r = Runnable.implement(
        $Runnable(run: done.complete, run$async: true),
      );
      handler.post(r);
      await done.future;
      samples.add(sw.elapsedMicroseconds);
      r.release();
    }
    results['callback_post_to_dart_async_median_us'] = median(samples);

    // Same, with a synchronous callback (the main Looper thread runs Dart).
    final syncSamples = <int>[];
    for (var i = 0; i < 300; i++) {
      final done = Completer<void>();
      final sw = Stopwatch()..start();
      final r = Runnable.implement(
        $Runnable(
          run: () {
            syncSamples.add(sw.elapsedMicroseconds);
            done.complete();
          },
        ),
      );
      handler.post(r);
      await done.future;
      r.release();
    }
    results['callback_post_to_dart_sync_median_us'] = median(syncSamples);

    // Pure Java -> Dart callback cost: Handler.dispatchMessage invokes the
    // Dart-implemented Handler.Callback synchronously on the calling thread.
    var handled = 0;
    final cb = Handler_Callback.implement(
      $Handler_Callback(
        handleMessage: (msg) {
          handled++;
          return true;
        },
      ),
    );
    final direct = Handler.new$Looper$Callback(Looper.getMainLooper()!, cb);
    final msg = Message.obtain()!;
    results['callback_sync_dispatch_ns'] = nsPerCall(
      20000,
      () => direct.dispatchMessage(msg),
    );
    expect(handled, greaterThan(20000));

    // ignore: avoid_print
    print('NAB_BENCH ${jsonEncode(results)}');
  });
}
