import 'dart:convert';
import 'dart:io' show ProcessInfo;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ios_slice/src/generated/apple.dart' as ios;
import 'package:objective_c/objective_c.dart' as objc;

/// Micro-benchmarks (TRD §35): generated objc_msgSend bindings vs. a
/// hand-written MethodChannel. Flutter supports only debug mode on the iOS
/// simulator, so these are JIT numbers. Prints one `NAB_BENCH {json}` line.
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

  test('benchmarks', () async {
    final results = <String, num>{};
    final view = ios.UIView.new$();
    results['msgsend_instance_getter_int_ns'] = nsPerCall(
      200000,
      () => view.tag,
    );
    results['msgsend_class_getter_object_ns'] = nsPerCall(
      50000,
      () => ios.NSProcessInfo.processInfo,
    );
    final vc = ios.UIViewController.new$();
    results['nsstring_roundtrip_ns'] = nsPerCall(20000, () {
      vc.title = 'Slice'.toNSString();
      vc.title!.toDartString();
    });
    results['struct_by_value_roundtrip_ns'] = nsPerCall(50000, () {
      view.frame = view.frame;
    });

    // NSData <-> Uint8List (TRD §36): one native copy in, a zero-copy view
    // out; objective_c's toList() copies.
    double msPer(int n, void Function() f) {
      f();
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        f();
      }
      return sw.elapsedMicroseconds / 1000 / n;
    }

    for (final (label, size) in [('1mb', 1 << 20), ('16mb', 16 << 20)]) {
      final data = Uint8List(size)..fillRange(0, size, 7);
      results['nsdata_from_bytes_${label}_ms'] = msPer(10, () {
        ios.nsDataFromBytes(data).ref.release();
      });
      final d = ios.nsDataFromBytes(data);
      results['nsdata_view_${label}_ms'] = msPer(10, () {
        if (ios.nsDataView(d).length != size) throw StateError('size');
      });
      results['nsdata_tolist_copy_${label}_ms'] = msPer(10, () {
        if (d.toList().length != size) throw StateError('size');
      });
    }

    // Memory per handle: RSS before/after 10k live NSObject handles.
    // Warm-up allocation first (heap growth), then 50k live handles.
    var warm = [for (var i = 0; i < 20000; i++) ios.NSOperationQueue.new$()];
    warm = [];
    final rss0 = ProcessInfo.currentRss;
    final keep = [for (var i = 0; i < 50000; i++) ios.NSOperationQueue.new$()];
    final rss1 = ProcessInfo.currentRss;
    results['rss_per_handle_bytes'] = ((rss1 - rss0) / keep.length).round();
    results['rss_handles_measured'] = keep.length + warm.length;

    const channel = MethodChannel('nab/bench');
    results['methodchannel_noop_us'] = await usPerAsyncCall(
      5000,
      () => channel.invokeMethod<void>('noop'),
    );
    results['methodchannel_view_tag_us'] = await usPerAsyncCall(
      5000,
      () => channel.invokeMethod<int>('viewTag'),
    );
    results['methodchannel_string_roundtrip_us'] = await usPerAsyncCall(
      5000,
      () => channel.invokeMethod<String>('echoString', 'Slice'),
    );
    expect(objc.NSString('x').toDartString(), 'x');
    // ignore: avoid_print
    print('NAB_BENCH ${jsonEncode(results)}');
  });
}
