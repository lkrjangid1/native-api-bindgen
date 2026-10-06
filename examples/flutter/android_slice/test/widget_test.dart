import 'package:android_slice/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Rendering only, with a fixed snapshot: native calls run on a device in
// integration_test/showcase_test.dart.
void main() {
  testWidgets('dashboard renders a device status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DeviceDashboard(
            status: (
              device: 'Google Pixel',
              apiLevel: 36,
              batteryPercent: 80,
              charging: true,
              availMemBytes: 1 << 30,
              totalMemBytes: 4 << 30,
              lowMemory: false,
              freeStorageBytes: 10 << 30,
              totalStorageBytes: 64 << 30,
              network: 'Wi-Fi · 30.0 Mbps down',
            ),
          ),
        ),
      ),
    );
    expect(find.text('Google Pixel'), findsOneWidget);
    expect(find.text('80% · charging'), findsOneWidget);
    expect(find.text('3.0 GB of 4.0 GB used'), findsOneWidget);
    expect(find.text('10.0 GB free of 64.0 GB'), findsOneWidget);
    expect(find.text('Wi-Fi · 30.0 Mbps down'), findsOneWidget);
  });
}
