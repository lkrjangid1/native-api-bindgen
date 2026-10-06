import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart'
    show Center, Directionality, SizedBox, TextDirection;
import 'package:integration_test/integration_test.dart';
import 'package:native_api_ui/native_api_ui.dart';
import 'package:ios_slice/slice.dart';
import 'package:ios_slice/src/generated/apple.dart' as ios;
import 'package:objective_c/objective_c.dart' as objc;

/// On-simulator tests: every call below goes through generated bindings
/// (objc_msgSend trampolines over package:objective_c) into Foundation and
/// UIKit on the running iOS runtime.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('UIDevice: strings, enum-typed property', () {
    final s = deviceSummary();
    expect(s['systemName'], 'iOS');
    expect(s['model'], contains('iPhone'));
    expect(s['idiom'], 'phone');
    expect(s['systemVersion'], isNotEmpty);
  });

  test(
    'main-actor members are checked off the main thread (debug, E013)',
    () async {
      expect(ios.isMainThread(), isTrue, reason: 'root isolate runs on main');
      ios.UIView.new$().tag = 1;
      final symbol = await Isolate.run(() {
        try {
          ios.UIView.new$().tag = 2;
          return 'no error';
        } on ios.NativeThreadingError catch (e) {
          return e.symbol;
        }
      });
      expect(symbol, contains('UIView'));
      // Foundation (not main-actor isolated) works from a background isolate.
      final name = await Isolate.run(
        () => ios.NSProcessInfo.processInfo.processName.toDartString(),
      );
      expect(name, isNotEmpty);
    },
  );

  testWidgets('native UI: a UILabel created through bindings is shown', (
    tester,
  ) async {
    final label = ios.UILabel.new$()..text = 'Hello native'.toNSString();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 240,
            height: 80,
            child: NativeView.ios(view: label),
          ),
        ),
      ),
    );
    for (var i = 0; i < 50 && label.window == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NativeView), findsOneWidget);
    expect(label.window, isNotNull);
    expect(label.text!.toDartString(), 'Hello native');
    expect(label.bounds.size.width, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  test('NSData <-> Uint8List', () {
    final bytes = Uint8List.fromList([1, 2, 255, 0]);
    final d = ios.nsDataFromBytes(bytes);
    expect(d.length, 4);
    expect(ios.nsDataView(d), bytes);
    expect(d.toList(), bytes);
  });

  group('Objective-C blocks', () {
    test('NS_NOESCAPE block runs synchronously', () {
      var ran = false;
      ios.UIView.performWithoutAnimation(() => ran = true);
      expect(ran, isTrue);
    });

    test('escaping completion block (listener) and its Future form', () async {
      final view = ios.UIView.new$();
      var animationsRan = false;
      // Escaping blocks are listener blocks: delivered asynchronously, so
      // UIKit's `animations` block runs after the call returns.
      final finished =
          await ios.UIView.animateWithDuration$animations$completionAsync(
            0.01,
            animations: () {
              animationsRan = true;
              view.alpha = 0.5;
            },
          );
      expect(finished, isA<bool>());
      for (var tries = 0; !animationsRan && tries < 100; tries++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(animationsRan, isTrue);
      expect(view.alpha, 0.5);
    });

    test('escaping block on a background queue (listener)', () async {
      final queue = ios.NSOperationQueue.new$();
      final done = <int>[];
      for (var i = 0; i < 5; i++) {
        queue.addOperationWithBlock(() => done.add(i));
      }
      queue.waitUntilAllOperationsAreFinished();
      // Listener blocks are delivered asynchronously to this isolate.
      for (var tries = 0; done.length < 5 && tries < 100; tries++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(done.toSet(), {0, 1, 2, 3, 4});
    });
  });

  test('NSProcessInfo: struct returned and passed by value', () {
    final info = ios.NSProcessInfo.processInfo;
    final v = info.operatingSystemVersion;
    expect(v.majorVersion, greaterThanOrEqualTo(13));
    expect(
      ios.UIDevice.currentDevice.systemVersion.toDartString(),
      startsWith('${v.majorVersion}.'),
    );
    expect(info.isOperatingSystemAtLeastVersion(v), isTrue);
    expect(info.processName.toDartString(), isNotEmpty);
  });

  test('UIView: CGRect by value through init and property', () {
    final view = ios.UIView.alloc().initWithFrame(rect(1, 2, 30, 40));
    final f = view.frame;
    expect(
      [f.origin.x, f.origin.y, f.size.width, f.size.height],
      [1.0, 2.0, 30.0, 40.0],
    );
    view.frame = rect(5, 6, 7, 8);
    expect(view.frame.size.height, 8.0);
  });

  test('UIView: primitive and NS_OPTIONS properties', () {
    final view = ios.UIView.new$();
    view.tag = 42;
    expect(view.tag, 42);
    expect(view.hidden, isFalse);
    view.hidden = true;
    expect(view.hidden, isTrue, reason: 'getter=isHidden selector');
    const mask =
        ios.UIViewAutoresizing.UIViewAutoresizingFlexibleWidth |
        ios.UIViewAutoresizing.UIViewAutoresizingFlexibleHeight;
    view.autoresizingMask = mask;
    expect(view.autoresizingMask, mask);
  });

  test('view hierarchy: object arguments, nullable returns, NSArray', () {
    final parent = ios.UIView.new$();
    final child = ios.UIView.new$();
    expect(child.superview, isNull);
    parent.addSubview(child);
    expect(parent.subviews.count, 1);
    expect(child.superview!.isEqual(parent), isTrue);
    child.removeFromSuperview();
    expect(child.superview, isNull);
    expect(buildViews(), 3);
  });

  test('nullable object property and class property', () {
    final view = ios.UIView.new$();
    expect(view.backgroundColor, isNull);
    final red = ios.UIColor.redColor;
    view.backgroundColor = red;
    expect(view.backgroundColor!.isEqual(red), isTrue);
    view.backgroundColor = null;
    expect(view.backgroundColor, isNull);
  });

  test('UIViewController: lazy view, nullable NSString title', () {
    final vc = ios.UIViewController.new$();
    expect(vc.viewLoaded, isFalse);
    final view = vc.view;
    expect(vc.viewLoaded, isTrue);
    expect(ios.UIView.isA(view), isTrue);
    expect(vc.title, isNull);
    vc.title = 'Slice'.toNSString();
    expect(vc.title!.toDartString(), 'Slice');
  });

  test('type checks: isA', () {
    final view = ios.UIView.new$();
    expect(ios.UIView.isA(view), isTrue);
    expect(ios.UIDevice.isA(view), isFalse);
    expect(ios.UIView.isA(null), isFalse);
    expect(ios.UIViewController.isA(ios.UIViewController.new$()), isTrue);
  });

  test('NSError ** out-parameter throws NativeObjCError', () {
    expect(listMissingDirectory(), startsWith('NSCocoaErrorDomain '));
    final ok = ios.NSFileManager.defaultManager.contentsOfDirectoryAtPath(
      '/'.toNSString(),
    );
    expect(ok, isNotNull);
  });

  test('availability guard: API newer than the runtime throws', () {
    // Generated members newer than the deployment target start with this
    // call (e.g. UIViewController.registerSceneAccessory: on iOS 27). Which
    // members exist depends on the Xcode SDK, so exercise the guard with a
    // version one above the running OS instead of a specific API.
    final v = ios.NSProcessInfo.processInfo.operatingSystemVersion;
    expect(
      () => objc.checkOsVersionInternal(
        'Test.newerThanRuntime',
        iOS: (false, (v.majorVersion + 1, 0, 0)),
      ),
      throwsA(isA<objc.OsVersionError>()),
    );
    expect(
      () => objc.checkOsVersionInternal(
        'Test.olderThanRuntime',
        iOS: (false, (v.majorVersion, 0, 0)),
      ),
      returnsNormally,
    );
  });

  test('lifecycle: explicit release, use-after-release, many objects', () {
    final view = ios.UIView.new$();
    view.ref.release();
    expect(() => view.tag, throwsA(isA<objc.UseAfterReleaseError>()));
    for (var i = 0; i < 10000; i++) {
      final v = ios.UIView.new$()..tag = i;
      expect(v.tag, i);
      v.ref.release();
    }
  });

  group('Swift-only APIs through generated @objc adapters', () {
    test('Swift class: init with labels, methods, properties, statics', () {
      final c = ios.NABSwiftFixtures_Counter.alloc().initWithStart(
        5,
        label: 'apples'.toNSString(),
      );
      expect(c.incrementBy(2), 7);
      expect(c.value, 7);
      expect(c.describePrefix(null).toDartString(), 'apples=7');
      c.label = 'pears'.toNSString();
      expect(c.describePrefix('#'.toNSString()).toDartString(), '#pears=7');
      expect(ios.NABSwiftFixtures_Counter.make().value, 0);
      expect(ios.NABSwiftFixtures_Counter.instances, 0);
    });

    test('Swift struct: value semantics in a box, mutating method', () {
      final t = ios.NABSwiftFixtures_Temperature.alloc().initWithCelsius(100);
      expect(t.fahrenheit, 212);
      final warmer = t.adding(5);
      expect(warmer.celsius, 105);
      expect(t.celsius, 100, reason: 'adding returns a new value');
      t.reset();
      expect(t.celsius, 0);
      t.celsius = 37;
      expect(t.fahrenheit, closeTo(98.6, 1e-9));
    });

    test('collections, raw-value enums, throws and async', () async {
      final c = ios.NABSwiftFixtures_Counter.alloc().initWithStart(
        12,
        label: 'c'.toNSString(),
      );
      // Collections cross as NSArray / NSDictionary.
      expect(c.values().count, 1);
      expect(
        (c.tags().objectForKey('c'.toNSString()) as objc.NSNumber).intValue,
        12,
      );
      final neighbors = c.neighbors();
      expect(neighbors.count, 2);
      expect(
        ios.NABSwiftFixtures_Counter.as(neighbors.objectAtIndex(1)).value,
        13,
      );
      expect(
        c
            .names(objc.NSArray.of(['a'.toNSString(), 'b'.toNSString()]))
            .toDartString(),
        'a,b',
      );
      // Raw-value enums cross as their raw value.
      expect(c.level(), ios.NABSwiftFixtures_Level.high);
      expect(ios.NABSwiftFixtures_Level.low, 1);
      expect(
        c.describeLevel(ios.NABSwiftFixtures_Level.low).toDartString(),
        'level 1',
      );
      expect(
        c.mood.toDartString(),
        ios.NABSwiftFixtures_Mood.happy.toDartString(),
      );
      c.mood = ios.NABSwiftFixtures_Mood.sad;
      expect(c.mood.toDartString(), 'sad');
      // throws -> NSError ** -> NativeObjCError.
      expect(c.checkLimit(20), isTrue);
      expect(() => c.checkLimit(5), throwsA(isA<ios.NativeObjCError>()));
      expect(c.duplicateNamed('d'.toNSString())!.label.toDartString(), 'd');
      expect(
        () => c.duplicateNamed(''.toNSString()),
        throwsA(isA<ios.NativeObjCError>()),
      );
      expect(
        () => ios.NABSwiftFixtures_Counter.alloc().initWithValidating(-1),
        throwsA(isA<ios.NativeObjCError>()),
      );
      // async -> completion handler -> Future (primitive results).
      expect(await c.laterWithCompletionAsync(), 12);
      await c.waitWithCompletionAsync();
      expect(await ios.NABSwiftFixtures_Counter.totalOfAsync(neighbors), 24);
    });

    test('adapted types as parameters and results', () {
      final c = ios.NABSwiftFixtures_Counter.alloc().initWithStart(
        30,
        label: 'c'.toNSString(),
      );
      expect(c.temperature().celsius, 30);
      expect(
        c.isAbove(ios.NABSwiftFixtures_Temperature.alloc().initWithCelsius(20)),
        isTrue,
      );
      expect(
        c.isAbove(ios.NABSwiftFixtures_Temperature.alloc().initWithCelsius(40)),
        isFalse,
      );
    });
  });
}
