import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/screens/device_b_screen.dart';
import 'package:rndscreeningap/screens/role_selection_screen.dart';
import 'package:rndscreeningap/theme/app_theme.dart';

import '../helpers/fakes.dart';

Future<void> _pump(WidgetTester tester) async {
  usePhoneSurface(tester, size: const Size(400, 900));
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.darkTheme, home: const RoleSelectionScreen()),
  );
}

void main() {
  testWidgets('shows the title, both transport tabs and both role cards',
      (tester) async {
    await _pump(tester);

    expect(find.textContaining('Live Screen Mirroring'), findsOneWidget);
    expect(find.text('WebSocket (IP)'), findsOneWidget);
    expect(find.text('Firebase (Cloud)'), findsOneWidget);
    expect(find.text('Device A: WebSocket Broadcaster'), findsOneWidget);
    expect(find.text('Device B: WebSocket Receiver'), findsOneWidget);
  });

  testWidgets('defaults to WebSocket mode', (tester) async {
    await _pump(tester);

    expect(find.byIcon(Icons.lan_rounded), findsOneWidget); // header logo
    expect(find.text('HOST / SENDER (LOCAL IP)'), findsOneWidget);
    expect(find.text('VIEWER (WEBSOCKET IP)'), findsOneWidget);
    expect(find.textContaining('Ultra Low Latency'), findsOneWidget);
  });

  testWidgets('switching to Firebase updates the cards, header and footer',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Firebase (Cloud)'));
    await tester.pumpAndSettle();

    expect(find.text('Device A: Firebase Broadcaster'), findsOneWidget);
    expect(find.text('Device B: Firebase Receiver'), findsOneWidget);
    expect(find.text('HOST / SENDER (FIREBASE CLOUD)'), findsOneWidget);
    expect(find.text('VIEWER (FIREBASE CLOUD)'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_rounded), findsWidgets);
    expect(find.textContaining('Powered by Firebase'), findsOneWidget);
    expect(find.text('Device A: WebSocket Broadcaster'), findsNothing);
  });

  testWidgets('can switch back from Firebase to WebSocket', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Firebase (Cloud)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebSocket (IP)'));
    await tester.pumpAndSettle();

    expect(find.text('Device A: WebSocket Broadcaster'), findsOneWidget);
    expect(find.text('Device A: Firebase Broadcaster'), findsNothing);
  });

  testWidgets('tapping the Device B card opens the WebSocket receiver',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Device B: WebSocket Receiver'));
    await tester.pumpAndSettle();

    final screen =
        tester.widget<DeviceBReceiverScreen>(find.byType(DeviceBReceiverScreen));
    expect(screen.transportMode.name, 'webSocket');
    expect(find.text('Device B: Receiver (WebSocket IP)'), findsOneWidget);

    // Back navigation returns to the role picker.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(RoleSelectionScreen), findsOneWidget);
  });

  // Opening the Device A card in WebSocket mode starts a real server on port
  // 8080 in initState, so that flow is covered in integration_test/ instead.
}
