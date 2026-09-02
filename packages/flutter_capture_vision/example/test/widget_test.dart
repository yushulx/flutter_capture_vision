import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_capture_vision_example/main.dart';

void main() {
  testWidgets('shows the three Capture Vision radio choices', (tester) async {
    await tester.pumpWidget(const CaptureVisionExampleApp());

    expect(find.text('Barcode'), findsOneWidget);
    expect(find.text('MRZ'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);
  });
}
