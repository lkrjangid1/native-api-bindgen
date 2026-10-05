import 'package:android_slice/main.dart';
import 'package:flutter_test/flutter_test.dart';

// Native calls only happen on button presses; on-device behaviour is covered by
// integration_test/slice_test.dart.
void main() {
  testWidgets('renders the action buttons', (tester) async {
    await tester.pumpWidget(const SliceApp());
    expect(find.text('Intent + Uri'), findsOneWidget);
    expect(find.text('Handler.post(Runnable)'), findsOneWidget);
  });
}
