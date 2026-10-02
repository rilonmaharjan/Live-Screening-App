import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/main.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('ScreenMirroringApp loads smoke test', (WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(const ScreenMirroringApp());
    expect(find.textContaining('Live Screen Mirroring'), findsOneWidget);
  });
}
