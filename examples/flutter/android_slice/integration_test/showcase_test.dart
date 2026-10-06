import 'package:android_slice/main.dart';
import 'package:android_slice/src/showcase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The showcase tasks against the real Android framework (emulator/device).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('device status: battery, memory, storage, network', () {
    final s = Showcase.deviceStatus();
    expect(s.device.trim(), isNotEmpty);
    expect(s.apiLevel, greaterThanOrEqualTo(24));
    expect(s.batteryPercent, inInclusiveRange(0, 100));
    expect(s.totalMemBytes, greaterThan(s.availMemBytes));
    expect(s.availMemBytes, greaterThan(0));
    expect(s.totalStorageBytes, greaterThan(s.freeStorageBytes));
    expect(s.network, isNotEmpty);
  });

  test('clipboard round trip', () {
    Showcase.copy('nab clipboard ✓');
    expect(Showcase.paste(), 'nab clipboard ✓');
  });

  test('SharedPreferences note round trip', () {
    final note = 'note ${DateTime.now().microsecondsSinceEpoch}';
    Showcase.saveNote(note);
    expect(Showcase.loadNote(), note);
  });

  test('vibrate uses VibrationEffect on API 26+', () {
    final r = Showcase.vibrate();
    expect(
      r,
      anyOf(
        'VibrationEffect.createOneShot (API 26+)',
        'no vibrator on this device',
      ),
    );
  });

  test(
    'text-to-speech initialises through a Dart OnInitListener',
    () async {
      await Speaker.instance.speak('native API bindgen');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets('showcase page shows the dashboard and runs a task', (
    tester,
  ) async {
    await tester.pumpWidget(const ShowcaseApp());
    await tester.pump();
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);

    await tester.tap(find.text('Copy, then paste back'));
    await tester.pump();
    expect(
      find.textContaining('Clipboard now holds: Hello from Dart'),
      findsOneWidget,
    );
    // Stop the 3 s refresh timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  // Last: these move the app to the background.
  test(
    'settings intents resolve: app permissions, then location settings',
    () async {
      // startActivity throws (ActivityNotFoundException) if nothing handles it.
      Showcase.openAppPermissions();
      await Future<void>.delayed(const Duration(seconds: 2));
      Showcase.openLocationSettings();
      await Future<void>.delayed(const Duration(seconds: 2));
    },
  );
}
