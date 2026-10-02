// End-to-end tests that run the real UI against real network sockets.
//
//   flutter test integration_test/app_test.dart -d <device-id>
//
// Notes
//  * They start a WebSocket server on port 8080, so the port must be free.
//  * They need dart:io sockets, so they run on Android / iOS / desktop but not
//    on web (the app itself cannot host a server in a browser either).
//  * They pump `ScreenMirroringApp` directly instead of calling `main()`,
//    because `main()` initialises Firebase, which needs a configured project.
//    The Firebase transport is covered by the unit + widget tests (fake
//    Firestore) rather than here.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rndscreeningap/main.dart';
import 'package:rndscreeningap/models/mirror_protocol.dart';
import 'package:rndscreeningap/services/network_service.dart';

const _port = 8080;

final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Pumps real frames until [condition] holds (network I/O is not driven by
/// pump, so `pumpAndSettle` alone is not enough).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $reason');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpUntilFound(WidgetTester tester, Finder finder,
        {Duration timeout = const Duration(seconds: 10)}) =>
    pumpUntil(tester, () => finder.evaluate().isNotEmpty,
        timeout: timeout, reason: finder.toString());

Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const ScreenMirroringApp());
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Navigation', () {
    testWidgets('role selection -> Device B (WebSocket) -> back', (tester) async {
      await launchApp(tester);
      expect(find.textContaining('Live Screen Mirroring'), findsOneWidget);

      await tester.tap(find.text('Device B: WebSocket Receiver'));
      await tester.pumpAndSettle();
      expect(find.text('Device B: Receiver (WebSocket IP)'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Device B: WebSocket Receiver'), findsOneWidget);
    });

    testWidgets('transport tabs swap the role cards', (tester) async {
      await launchApp(tester);

      await tester.tap(find.text('Firebase (Cloud)'));
      await tester.pumpAndSettle();
      expect(find.text('Device A: Firebase Broadcaster'), findsOneWidget);

      await tester.tap(find.text('WebSocket (IP)'));
      await tester.pumpAndSettle();
      expect(find.text('Device A: WebSocket Broadcaster'), findsOneWidget);
    });
  });

  group('Device B input validation', () {
    testWidgets('an unfinished IP is rejected without touching the network',
        (tester) async {
      await launchApp(tester);
      await tester.tap(find.text('Device B: WebSocket Receiver'));
      await tester.pumpAndSettle();

      // Field is pre-filled with "192.168.1." which is not a complete address.
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid IP address'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('an unreachable host reports a failure', (tester) async {
      await launchApp(tester);
      await tester.tap(find.text('Device B: WebSocket Receiver'));
      await tester.pumpAndSettle();

      // Nothing listens on this port.
      await tester.enterText(find.byType(TextField), '127.0.0.1:9');
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.textContaining('Connection failed'));

      expect(find.text('Connect'), findsOneWidget);
    });
  });

  group('Device A screen (real WebSocket server)', () {
    testWidgets('hosts a server, counts clients, and exercises the dashboard',
        (tester) async {
      await launchApp(tester);
      await tester.tap(find.text('Device A: WebSocket Broadcaster'));
      await tester.pumpAndSettle();
      expect(find.text('Device A: Broadcaster'), findsOneWidget);

      // The detected LAN IP is displayed once the server is up.
      final ipText = find.byWidgetPredicate((w) =>
          w is Text &&
          RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(w.data ?? ''));
      await pumpUntilFound(tester, ipText);

      // A real client joins -> the counter updates.
      final client = WebSocketClientService();
      addTearDown(client.disconnect);
      expect(await client.connect('127.0.0.1:$_port'), isTrue);
      await pumpUntilFound(
          tester, find.text('Connected WebSocket Clients: 1'));

      // Dashboard controls respond.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      // Museum map tab: select a place and open the details panel.
      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ActionChip, 'All Places'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, 'HOSPITAL'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(ActionChip, 'HOSPITAL'));
      await tester.tap(find.widgetWithText(ActionChip, 'HOSPITAL'));
      await tester.pumpAndSettle();
      expect(find.text('Read More'), findsOneWidget);

      // Client leaves -> counter drops back.
      await client.disconnect();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      await pumpUntilFound(
          tester, find.text('Connected WebSocket Clients: 0'));

      // Leaving the screen shuts the server down (port becomes free again).
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Give the async stopServer() a moment to finish, then confirm.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final probe = WebSocketClientService();
      expect(await probe.connect('127.0.0.1:$_port'), isFalse);
    });
  });

  group('Device A -> Device B end to end', () {
    late WebSocketServerService host;

    setUp(() async {
      host = WebSocketServerService();
      expect(await host.startServer(port: _port), isTrue,
          reason: 'port $_port must be free to run this test');
    });

    tearDown(() => host.stopServer());

    testWidgets('Device B screen connects and mirrors frames and touches',
        (tester) async {
      await launchApp(tester);
      await tester.tap(find.text('Device B: WebSocket Receiver'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '127.0.0.1:$_port');
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.text('Disconnect'));
      expect(find.text('Connected to Device A!'), findsOneWidget);
      expect(find.text('WEBSOCKET STREAM LIVE'), findsOneWidget);
      await pumpUntil(tester, () => host.clientCount == 1,
          reason: 'host to register the client');

      // A frame from the host appears on Device B.
      await host.broadcastFrame(FramePacket(
        imageBytes: _tinyPng,
        aspectRatio: 0.5,
        width: 540,
        height: 960,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      await pumpUntilFound(tester, find.textContaining('Resolution: 540x960'));
      expect(find.byType(Image), findsOneWidget);

      // A touch on the host shows up as an active touch on Device B...
      GesturePacket touch(PointerAction action) => GesturePacket(
            action: action,
            pointerId: 1,
            normalizedX: 0.4,
            normalizedY: 0.6,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
      await host.broadcastGesture(touch(PointerAction.down));
      await pumpUntilFound(tester, find.text('Active Touches: 1'));

      // ...and disappears on release.
      await host.broadcastGesture(touch(PointerAction.up));
      await pumpUntilFound(tester, find.text('Active Touches: 0'));

      // Disconnecting from the UI is reflected on the host.
      await tester.tap(find.text('Disconnect'));
      await pumpUntilFound(tester, find.text('Connect'));
      await pumpUntil(tester, () => host.clientCount == 0,
          reason: 'host to drop the client');
    });

    testWidgets('Device B screen notices when the host stops', (tester) async {
      await launchApp(tester);
      await tester.tap(find.text('Device B: WebSocket Receiver'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '127.0.0.1:$_port');
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.text('Disconnect'));

      await host.stopServer();

      await pumpUntilFound(tester, find.text('Connect'));
      expect(find.text('Disconnect'), findsNothing);
    });
  });
}
