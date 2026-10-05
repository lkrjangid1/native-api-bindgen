import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ios_slice/main.dart';
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
    expect([f.origin.x, f.origin.y, f.size.width, f.size.height], [
      1.0,
      2.0,
      30.0,
      40.0,
    ]);
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
    final v = ios.NSProcessInfo.processInfo.operatingSystemVersion;
    final vc = ios.UIViewController.new$();
    if (v.majorVersion < 27) {
      expect(
        () => vc.registerSceneAccessory(ios.UIView.new$()),
        throwsA(isA<objc.OsVersionError>()),
      );
    } else {
      markTestSkipped('runtime is iOS ${v.majorVersion}: guard not triggered');
    }
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

    test('adapted types as parameters and results', () {
      final c = ios.NABSwiftFixtures_Counter.alloc().initWithStart(
        30,
        label: 'c'.toNSString(),
      );
      expect(c.temperature().celsius, 30);
      expect(c.isAbove(ios.NABSwiftFixtures_Temperature.alloc().initWithCelsius(20)), isTrue);
      expect(c.isAbove(ios.NABSwiftFixtures_Temperature.alloc().initWithCelsius(40)), isFalse);
    });
  });

  testWidgets('app renders values from the bindings', (tester) async {
    await tester.pumpWidget(const SliceApp());
    expect(find.text('iOS'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.textContaining('NSCocoaErrorDomain'), findsOneWidget);
  });
}
