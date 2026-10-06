import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ios_slice/main.dart';
import 'package:ios_slice/showcase.dart';

/// The showcase tasks against the real iOS runtime (simulator/device).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('device status: system, memory, CPUs, uptime, storage', () {
    final s = Showcase.deviceStatus();
    expect(s.system, startsWith('iOS '));
    expect(s.physicalMemoryBytes, greaterThan(1 << 30));
    expect(s.processors, greaterThan(0));
    expect(s.uptime, greaterThan(Duration.zero));
    expect(s.totalStorageBytes, greaterThan(s.freeStorageBytes!));
    expect(s.thermalState, isNotEmpty);
  });

  test('pasteboard round trip', () {
    Showcase.copy('nab pasteboard ✓');
    expect(Showcase.paste(), 'nab pasteboard ✓');
  });

  test('NSUserDefaults note round trip', () {
    final note = 'note ${DateTime.now().microsecondsSinceEpoch}';
    Showcase.saveNote(note);
    expect(Showcase.loadNote(), note);
  });

  test('haptics run on the main thread without errors', Showcase.haptics);

  test('AVSpeechSynthesizer starts speaking', () async {
    Speaker.instance.speak('native API bindgen');
    var spoke = false;
    for (var i = 0; i < 40 && !spoke; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      spoke = Speaker.instance.speaking;
    }
    expect(spoke, isTrue);
  });

  testWidgets('showcase page: dashboard, clipboard task, share sheet', (
    tester,
  ) async {
    await tester.pumpWidget(const ShowcaseApp());
    await tester.pump();
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('Storage'), findsOneWidget);
    expect(find.textContaining('cores'), findsOneWidget);

    await tester.tap(find.text('Copy, then paste back'));
    await tester.pump();
    expect(
      find.textContaining('Pasteboard now holds: Hello from Dart'),
      findsOneWidget,
    );

    // The share sheet is presented natively over the Flutter view.
    await Showcase.share('nab share test');
    // Stop the 3 s refresh timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  // Last: this moves the app to the background.
  test('app settings page opens (location permission lives there)', () async {
    expect(await Showcase.openAppSettings(), isTrue);
  });
}
