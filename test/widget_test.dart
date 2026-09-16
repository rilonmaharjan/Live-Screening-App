import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/main.dart';

void main() {
  testWidgets('ScreenMirroringApp loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ScreenMirroringApp());
    expect(find.textContaining('Live Screen Mirroring'), findsOneWidget);
  });
}
