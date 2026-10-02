// End-to-end tests that run the real UI against real network sockets.
//
//   flutter test integration_test/app_test.dart -d <device-id>
//
// Everything lives in this one file:
//   1. shared helpers (pumping, navigation, packet factories)
//   2. Device A / Device B helpers
//   3. Museum-map helpers
//   4. test groups: role selection, navigation, Device B, Device A dashboard,
//      Device A -> Device B end to end, service layer, protocol models,
//      and the detailed Museum Map suite.
//
// Notes
//  * They start a WebSocket server on port 8080, so the port must be free.
//  * They need dart:io sockets, so they run on Android / iOS / desktop but not
//    on web (the app itself cannot host a server in a browser either).
//  * They pump `ScreenMirroringApp` directly instead of calling `main()`,
//    because `main()` initialises Firebase, which needs a configured project.
//    The Firebase transport is covered by the unit + widget tests (fake
//    Firestore) rather than here. For the same reason the Firebase Device A /
//    Device B screens are not opened here - only the Firebase *role-selection*
//    UI is checked.
//  * Device B runs a repeating animation once a frame is shown, so never call
//    pumpAndSettle() on it after the first frame arrives - use pumpFor /
//    pumpUntil instead.
//  * MuseumMapView keeps its details panel in the tree (just slid off-screen)
//    while "closed", so map tests decide visibility by position (onScreen).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rndscreeningap/main.dart';
import 'package:rndscreeningap/models/mirror_protocol.dart';
import 'package:rndscreeningap/models/museum_item.dart';
import 'package:rndscreeningap/services/network_service.dart';
import 'package:rndscreeningap/theme/app_theme.dart';
import 'package:rndscreeningap/widgets/gesture_overlay_painter.dart';
import 'package:rndscreeningap/widgets/museum_map_view.dart';
import 'package:rndscreeningap/widgets/museum_poi.dart';

// ===========================================================================
// 1. Shared helpers
// ===========================================================================

const kPort = 8080;

final Uint8List kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Matches the detected LAN IP shown on the Device A status card.
final Finder kIpText = find.byWidgetPredicate((w) =>
    w is Text && RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(w.data ?? ''));

// ---------------------------------------------------------------------------
// Pumping helpers.
//
// IMPORTANT: once Device B shows a frame, `LiveGestureOverlay` runs a repeating
// animation, so `pumpAndSettle()` would never return on that screen. Use
// `pumpFor` / `pumpUntil` there.
// ---------------------------------------------------------------------------

/// Pumps real frames until [condition] holds (network I/O is not driven by
/// `pump`, so `pumpAndSettle` alone is not enough).
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
        timeout: timeout, reason: 'to find $finder');

Future<void> pumpUntilGone(WidgetTester tester, Finder finder,
        {Duration timeout = const Duration(seconds: 10)}) =>
    pumpUntil(tester, () => finder.evaluate().isEmpty,
        timeout: timeout, reason: 'to lose $finder');

/// Pumps for a fixed wall-clock duration (safe with repeating animations).
Future<void> pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Polling wait for plain `test()` cases that have no WidgetTester.
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Blocks until nothing is listening on [port] (the previous test's server has
/// finished shutting down).
Future<void> waitForPortFree({
  int port = kPort,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      final s = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 300));
      s.destroy();
    } catch (_) {
      return; // refused -> free
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('Port $port is still in use after $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
}

/// Fixes the logical screen size for the test (reset automatically).
void setScreen(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

// ---------------------------------------------------------------------------
// App navigation helpers
// ---------------------------------------------------------------------------

Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const ScreenMirroringApp());
  await tester.pumpAndSettle();
}

Future<void> openDeviceA(WidgetTester tester) async {
  await tester.tap(find.text('Device A: WebSocket Broadcaster'));
  await tester.pumpAndSettle();
}

Future<void> openDeviceB(WidgetTester tester) async {
  await tester.tap(find.text('Device B: WebSocket Receiver'));
  await tester.pumpAndSettle();
}

/// Pops the current route and gives async server shutdown a moment.
Future<void> leaveScreen(WidgetTester tester) async {
  await tester.pageBack();
  await tester.pumpAndSettle();
  await pumpFor(tester, const Duration(milliseconds: 400));
}

void clearSnackBars(WidgetTester tester) {
  final ctx = tester.element(find.byType(Scaffold).first);
  ScaffoldMessenger.of(ctx).clearSnackBars();
}

// ---------------------------------------------------------------------------
// Packet factories
// ---------------------------------------------------------------------------

FramePacket makeFrame({
  int width = 540,
  int height = 960,
  int? timestamp,
  Uint8List? bytes,
}) =>
    FramePacket(
      imageBytes: bytes ?? kTinyPng,
      aspectRatio: width / height,
      width: width,
      height: height,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );

GesturePacket makeGesture(
  PointerAction action, {
  int id = 1,
  double x = 0.4,
  double y = 0.6,
  double scrollDx = 0,
  double scrollDy = 0,
}) =>
    GesturePacket(
      action: action,
      pointerId: id,
      normalizedX: x,
      normalizedY: y,
      scrollDeltaX: scrollDx,
      scrollDeltaY: scrollDy,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

// ===========================================================================
// 2. Device A / Device B helpers
// ===========================================================================

Future<void> connectDeviceB(WidgetTester tester, String target) async {
  await tester.enterText(find.byType(TextField), target);
  await tester.tap(find.text('Connect'));
  await pumpUntilFound(tester, find.text('Disconnect'));
}

Future<void> disconnectDeviceB(WidgetTester tester) async {
  await tester.tap(find.text('Disconnect'));
  await pumpUntilFound(tester, find.text('Connect'));
}

Future<void> chooseFit(WidgetTester tester, String menuLabel) async {
  await tester.tap(find.byTooltip('Aspect Ratio Fitting'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text(menuLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

BoxFit currentFit(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).fit!;

int latencyMs(WidgetTester tester) {
  final txt = tester.widget<Text>(find.textContaining('Latency:')).data!;
  return int.parse(RegExp(r'Latency: (\d+)ms').firstMatch(txt)!.group(1)!);
}

int syncLevel(WidgetTester tester) {
  final txt = tester
      .widget<Text>(find.byWidgetPredicate(
          (w) => w is Text && (w.data ?? '').startsWith('Sync Level:')))
      .data!;
  return int.parse(RegExp(r'(\d+)%').firstMatch(txt)!.group(1)!);
}

Future<void> dragSlider(WidgetTester tester, double dx) async {
  await tester.ensureVisible(find.byType(Slider));
  await tester.pumpAndSettle();
  await tester.drag(find.byType(Slider), Offset(dx, 0));
  await tester.pump();
}

/// The Device A drawing pad's CustomPaint (painter class is private).
final Finder _drawingCanvas = find.byWidgetPredicate((w) =>
    w is CustomPaint && w.painter.runtimeType.toString() == '_DrawingPainter');

List<Offset?> drawnPoints(WidgetTester tester) =>
    ((tester.widget<CustomPaint>(_drawingCanvas).painter as dynamic).points
            as List)
        .cast<Offset?>();

Future<void> drawStroke(WidgetTester tester, Offset delta) async {
  await tester.ensureVisible(_drawingCanvas);
  await tester.pumpAndSettle();
  // Horizontal so the parent vertical scroll view does not steal the drag.
  await tester.drag(_drawingCanvas, delta);
  await tester.pump();
}

// ---------------------------------------------------------------------------

// ===========================================================================
// 3. Museum-map helpers
// ===========================================================================

// ---------------------------------------------------------------------------
// Finders & readers
// ---------------------------------------------------------------------------

Finder chip(String label) => find.widgetWithText(ActionChip, label);

/// The pin drawn on the map itself (not the chip in the top bar).
Finder pin(String tag) => find.descendant(
    of: find.byType(InteractiveViewer), matching: find.text(tag));

Matrix4 matrixOf(WidgetTester t) => t
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value;

double scaleOf(WidgetTester t) => matrixOf(t).getMaxScaleOnAxis();

Rect mapRect(WidgetTester t) => t.getRect(find.byType(MuseumMapView));

Color? chipColor(WidgetTester t, String label) =>
    t.widget<ActionChip>(chip(label)).backgroundColor;

double pinScale(WidgetTester t, String tag) => t
    .widget<AnimatedScale>(
        find.ancestor(of: pin(tag), matching: find.byType(AnimatedScale)))
    .scale;

/// True if any match has its centre inside the visible map area.
bool onScreen(WidgetTester t, Finder finder) {
  final area = mapRect(t);
  for (final e in finder.evaluate()) {
    final box = e.renderObject;
    if (box is RenderBox && box.attached && box.hasSize) {
      final c = box.localToGlobal(box.size.center(Offset.zero));
      if (area.contains(c)) return true;
    }
  }
  return false;
}

/// Rect of the first match whose centre is inside the visible map area.
Rect? onScreenRect(WidgetTester t, Finder finder) {
  final area = mapRect(t);
  for (final e in finder.evaluate()) {
    final box = e.renderObject;
    if (box is RenderBox && box.attached && box.hasSize) {
      final topLeft = box.localToGlobal(Offset.zero);
      final r = topLeft & box.size;
      if (area.contains(r.center)) return r;
    }
  }
  return null;
}

bool panelVisible(WidgetTester t) =>
    find.text('Overview').evaluate().isNotEmpty &&
    onScreen(t, find.text('Overview'));

/// Scale the map zooms to when a POI is selected (see _zoomToPoi).
double expectedSelectScale(double viewportWidth) =>
    viewportWidth >= 600 ? 1.6 : (viewportWidth < 500 ? 1.85 : 1.6);

double expectedPanelWidth(double viewportWidth) =>
    viewportWidth > 600 ? 380 : viewportWidth * 0.88;

const _unselectedChip = Color(0xFF1E293B);
final _allPlacesSelected = Colors.teal.withValues(alpha: 0.3);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

Future<void> pumpMap(WidgetTester tester,
    {Size size = const Size(390, 780)}) async {
  setScreen(tester, size);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(body: MuseumMapView(pois: MuseumPoi.samplePois)),
  ));
  await tester.pumpAndSettle();
}

Future<void> selectViaChip(WidgetTester tester, MuseumPoi poi) async {
  final f = chip(poi.tag);
  await tester.ensureVisible(f); // chip bar scrolls horizontally on phones
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> selectViaPin(WidgetTester tester, MuseumPoi poi) async {
  await tester.tap(pin(poi.tag));
  await tester.pumpAndSettle();
}

Future<void> resetViaChip(WidgetTester tester) async {
  final f = chip('All Places');
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> openPanel(WidgetTester tester) async {
  await tester.tap(find.text('Read More'));
  await tester.pumpAndSettle();
}

Future<void> closePanel(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Close details'));
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Assertions
// ---------------------------------------------------------------------------

void expectCalloutFor(WidgetTester tester, MuseumPoi poi) {
  expect(onScreen(tester, find.text(poi.name)), isTrue,
      reason: '${poi.name} should be in the callout');
  expect(find.text(poi.category.toUpperCase()), findsOneWidget);
  expect(find.text(poi.shortDescription), findsOneWidget);
  expect(find.text('• ${poi.zone}'), findsOneWidget);
  expect(onScreen(tester, find.text('${poi.rating}')), isTrue);
  expect(find.text('Read More'), findsOneWidget);
  expect(panelVisible(tester), isFalse, reason: 'panel must start closed');
}

void expectOnlySelected(WidgetTester tester, MuseumPoi? selected) {
  expect(chipColor(tester, 'All Places'),
      selected == null ? _allPlacesSelected : _unselectedChip);
  for (final p in MuseumPoi.samplePois) {
    final isSel = p.id == selected?.id;
    expect(chipColor(tester, p.tag), isSel ? p.color : _unselectedChip,
        reason: 'chip ${p.tag} selected=$isSel');
    expect(pinScale(tester, p.tag), isSel ? 1.35 : 1.0,
        reason: 'pin ${p.tag} selected=$isSel');
  }
}

void expectPanelFor(WidgetTester tester, MuseumPoi poi) {
  expect(panelVisible(tester), isTrue);
  expect(find.text('Overview'), findsOneWidget);
  expect(find.text(poi.fullDescription), findsOneWidget);
  expect(find.text('Key Highlights'), findsOneWidget);
  for (final h in poi.highlights) {
    expect(find.text(h), findsOneWidget, reason: 'highlight "$h"');
  }
  expect(find.text('Operating Hours'), findsOneWidget);
  expect(find.text(poi.openHours), findsOneWidget);
  expect(find.text(poi.zone), findsOneWidget);
  expect(find.text(poi.category), findsOneWidget);
  expect(find.text('Directions'), findsOneWidget);
  expect(find.byIcon(Icons.bookmark_add_rounded), findsOneWidget);
  // The callout is replaced by the panel.
  expect(find.text('Read More'), findsNothing);
}

// ---------------------------------------------------------------------------


// ===========================================================================
// Tests
// ===========================================================================

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final pois = MuseumPoi.samplePois;


  // =========================================================================
  group('Role selection screen', () {
    testWidgets('WebSocket mode is the default and shows its copy',
        (tester) async {
      await launchApp(tester);

      expect(find.textContaining('Live Screen Mirroring'), findsOneWidget);
      expect(find.textContaining('Local Wi-Fi / IP WebSocket'), findsOneWidget);
      expect(find.text('WebSocket (IP)'), findsOneWidget);
      expect(find.text('Firebase (Cloud)'), findsOneWidget);

      expect(find.text('Device A: WebSocket Broadcaster'), findsOneWidget);
      expect(find.text('Device B: WebSocket Receiver'), findsOneWidget);
      expect(find.text('HOST / SENDER (LOCAL IP)'), findsOneWidget);
      expect(find.text('VIEWER (WEBSOCKET IP)'), findsOneWidget);
      expect(find.textContaining('ws://ip:port'), findsOneWidget);
      expect(find.textContaining('192.168.1.50:8080'), findsOneWidget);
      expect(find.text('WebSocket IP Direct Mode • Ultra Low Latency'),
          findsOneWidget);

      // Header / footer icons for this mode.
      expect(find.byIcon(Icons.lan_rounded), findsOneWidget);
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsNothing);
    });

    testWidgets('Firebase tab swaps every piece of copy', (tester) async {
      await launchApp(tester);
      await tester.tap(find.text('Firebase (Cloud)'));
      await tester.pumpAndSettle();

      expect(find.text('Device A: Firebase Broadcaster'), findsOneWidget);
      expect(find.text('Device B: Firebase Receiver'), findsOneWidget);
      expect(find.text('HOST / SENDER (FIREBASE CLOUD)'), findsOneWidget);
      expect(find.text('VIEWER (FIREBASE CLOUD)'), findsOneWidget);
      expect(find.textContaining('Firebase Cloud Firestore across any internet'),
          findsOneWidget);
      expect(find.text('Powered by Firebase Cloud Firestore Sync'),
          findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsNWidgets(2));

      // Nothing WebSocket-specific is left behind.
      expect(find.text('Device A: WebSocket Broadcaster'), findsNothing);
      expect(find.text('Device B: WebSocket Receiver'), findsNothing);
      expect(find.text('HOST / SENDER (LOCAL IP)'), findsNothing);
      expect(find.byIcon(Icons.lan_rounded), findsNothing);
      expect(find.byIcon(Icons.bolt_rounded), findsNothing);
    });

    testWidgets('toggling tabs repeatedly stays consistent', (tester) async {
      await launchApp(tester);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Firebase (Cloud)'));
        await tester.pumpAndSettle();
        expect(find.text('Device A: Firebase Broadcaster'), findsOneWidget);
        await tester.tap(find.text('WebSocket (IP)'));
        await tester.pumpAndSettle();
        expect(find.text('Device A: WebSocket Broadcaster'), findsOneWidget);
      }
    });

    testWidgets('mode is remembered after visiting and leaving Device B',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Device B: WebSocket Receiver'), findsOneWidget);
      expect(find.text('Device A: WebSocket Broadcaster'), findsOneWidget);
    });
  });

  // =========================================================================
  group('Navigation', () {
    testWidgets('role selection -> Device B (WebSocket) -> back',
        (tester) async {
      await launchApp(tester);
      expect(find.textContaining('Live Screen Mirroring'), findsOneWidget);

      await openDeviceB(tester);
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

    testWidgets('role selection -> Device A -> back frees the port',
        (tester) async {
      await waitForPortFree();
      await launchApp(tester);
      await openDeviceA(tester);
      expect(find.text('Device A: Broadcaster'), findsOneWidget);
      await pumpUntilFound(tester, kIpText);

      await leaveScreen(tester);
      expect(find.text('Device A: WebSocket Broadcaster'), findsOneWidget);
      await waitForPortFree();
    });
  });

  // =========================================================================
  group('Device B screen (no host running)', () {
    testWidgets('initial state', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '192.168.1.');
      expect(field.enabled, isTrue);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);

      // Footer status + centre placeholder.
      expect(find.text('Enter Host IP (e.g. 192.168.1.50:8080) and tap Connect'),
          findsOneWidget);
      expect(
          find.text(
              'Enter Host IP Address (e.g. 192.168.1.50:8080) and tap Connect.'),
          findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);

      // No stream UI before connecting.
      expect(find.byType(Image), findsNothing);
      expect(find.text('WEBSOCKET STREAM LIVE'), findsNothing);
      expect(find.byType(LiveGestureOverlay), findsNothing);
    });

    testWidgets('app-bar actions are present', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      expect(find.byTooltip('Toggle Telemetry Overlay'), findsOneWidget);
      expect(find.byTooltip('Aspect Ratio Fitting'), findsOneWidget);
    });

    testWidgets('an unfinished IP is rejected without touching the network',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);

      // Field is pre-filled with "192.168.1." which is not a complete address.
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid IP address'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('an empty field does nothing', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);
    });

    testWidgets('an unreachable host reports a failure', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);

      // Nothing listens on this port.
      await tester.enterText(find.byType(TextField), '127.0.0.1:9');
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.textContaining('Connection failed'));

      expect(find.text('Connect'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue,
          reason: 'user can edit the address and retry');
    });

    testWidgets('failed attempt can be retried with a new address',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await tester.enterText(find.byType(TextField), '127.0.0.1:9');
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.textContaining('Connection failed'));

      await tester.enterText(find.byType(TextField), '127.0.0.1:10');
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(
          tester, find.textContaining('Cannot reach ws://127.0.0.1:10'));
      expect(find.text('Connect'), findsOneWidget);
    });
  });

  // =========================================================================
  group('Device A dashboard (real WebSocket server)', () {
    setUp(() async => waitForPortFree());

    testWidgets('hosts a server, counts clients, and exercises the dashboard',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      expect(find.text('Device A: Broadcaster'), findsOneWidget);

      // The detected LAN IP is displayed once the server is up.
      await pumpUntilFound(tester, kIpText);

      // A real client joins -> the counter updates.
      final client = WebSocketClientService();
      addTearDown(client.disconnect);
      expect(await client.connect('127.0.0.1:$kPort'), isTrue);
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
      expect(await probe.connect('127.0.0.1:$kPort'), isFalse);
    });

    testWidgets('static content: cards, headings, labels', (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await pumpUntilFound(tester, kIpText);

      expect(find.text('LOCAL WI-FI ADDRESS (WEBSOCKET)'), findsOneWidget);
      expect(find.text('Connected WebSocket Clients: 0'), findsOneWidget);
      expect(find.text('Interactive UI Controls'), findsOneWidget);
      expect(find.text('Host Feature Toggle:'), findsOneWidget);
      expect(find.text('Sync Level: 65%'), findsOneWidget);
      expect(find.text('Museum Highlights'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Museum Map'), findsOneWidget);
      expect(find.byTooltip('Copy IP'), findsOneWidget);

      await leaveScreen(tester);
    });

    testWidgets('client counter follows several clients joining and leaving',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await pumpUntilFound(tester, kIpText);

      final a = WebSocketClientService();
      final b = WebSocketClientService();
      final c = WebSocketClientService();
      addTearDown(a.disconnect);
      addTearDown(b.disconnect);
      addTearDown(c.disconnect);

      expect(await a.connect('127.0.0.1:$kPort'), isTrue);
      await pumpUntilFound(tester, find.text('Connected WebSocket Clients: 1'));
      expect(await b.connect('127.0.0.1:$kPort'), isTrue);
      await pumpUntilFound(tester, find.text('Connected WebSocket Clients: 2'));
      expect(await c.connect('127.0.0.1:$kPort'), isTrue);
      await pumpUntilFound(tester, find.text('Connected WebSocket Clients: 3'));

      await b.disconnect();
      await pumpUntilFound(tester, find.text('Connected WebSocket Clients: 2'));
      await a.disconnect();
      await c.disconnect();
      await pumpUntilFound(tester, find.text('Connected WebSocket Clients: 0'));

      await leaveScreen(tester);
    });

    testWidgets('copy button puts the displayed IP on the clipboard',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await launchApp(tester);
      await openDeviceA(tester);
      await pumpUntilFound(tester, kIpText);
      final shownIp = tester.widget<Text>(kIpText).data!;

      await tester.tap(find.byTooltip('Copy IP'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(copied, shownIp);
      expect(find.text('IP Address copied to clipboard!'), findsOneWidget);

      await leaveScreen(tester);
    });

    testWidgets('host feature switch toggles on and off', (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);

      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await leaveScreen(tester);
    });

    testWidgets('sync slider updates its label and clamps at 0 and 100',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      expect(syncLevel(tester), 65);

      await dragSlider(tester, -800);
      expect(syncLevel(tester), 0);
      expect(find.text('Sync Level: 0%'), findsOneWidget);

      await dragSlider(tester, 1600);
      expect(syncLevel(tester), 100);

      await tester.tap(find.byType(Slider)); // centre of the track
      await tester.pump();
      expect(syncLevel(tester), inInclusiveRange(48, 52));

      await leaveScreen(tester);
    });

    testWidgets('Museum Highlights: every tile shows a "Selected" snackbar',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);

      for (final item in MuseumItem.sampleItems) {
        final tile = find.text(item.name);
        expect(tile, findsOneWidget, reason: 'tile for ${item.name}');
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Selected ${item.name}'), findsOneWidget);
        clearSnackBars(tester);
        await tester.pumpAndSettle();
      }

      await leaveScreen(tester);
    });

    testWidgets('drawing pad records strokes and Clear wipes them',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      expect(find.text('Live Drawing Pad'), findsOneWidget);
      expect(drawnPoints(tester), isEmpty);

      await drawStroke(tester, const Offset(120, 0));
      final first = drawnPoints(tester);
      expect(first.whereType<Offset>().length, greaterThanOrEqualTo(2));
      expect(first.last, isNull, reason: 'stroke is terminated on pan end');

      await drawStroke(tester, const Offset(-90, 0));
      final second = drawnPoints(tester);
      expect(second.length, greaterThan(first.length));
      expect(second.where((p) => p == null).length, 2,
          reason: 'one separator per stroke');

      await tester.ensureVisible(find.text('Clear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(drawnPoints(tester), isEmpty);

      await leaveScreen(tester);
    });

    testWidgets('dashboard state survives switching to the map and back',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);

      await tester.tap(find.byType(Switch)); // -> off
      await tester.pump();
      await dragSlider(tester, -800); // -> 0%
      await drawStroke(tester, const Offset(100, 0));
      final pointsBefore = drawnPoints(tester).length;

      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();
      expect(find.text('Interactive UI Controls'), findsNothing);
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(syncLevel(tester), 0);
      expect(drawnPoints(tester).length, pointsBefore);

      await leaveScreen(tester);
    });

    testWidgets('leaving and re-entering restarts the server',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await pumpUntilFound(tester, kIpText);
      await leaveScreen(tester);
      await waitForPortFree();

      await openDeviceA(tester);
      await pumpUntilFound(tester, kIpText);
      final client = WebSocketClientService();
      addTearDown(client.disconnect);
      expect(await client.connect('127.0.0.1:$kPort'), isTrue);
      await pumpUntilFound(tester, find.text('Connected WebSocket Clients: 1'));

      await leaveScreen(tester);
    });

    testWidgets('leaving Device A disconnects its clients', (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await pumpUntilFound(tester, kIpText);

      String? lastStatus;
      final client = WebSocketClientService()
        ..onStatusChanged = (ok, s) => lastStatus = s;
      addTearDown(client.disconnect);
      expect(await client.connect('127.0.0.1:$kPort'), isTrue);
      await pumpUntilFound(tester, find.text('Connected WebSocket Clients: 1'));

      await leaveScreen(tester);

      await pumpUntil(tester, () => !client.isConnected,
          reason: 'client to notice the host going away');
      expect(lastStatus, 'Disconnected from host');
    });

    // KNOWN GAP: DeviceABroadcasterScreen creates a FrameStreamerController
    // but never attaches its `repaintBoundaryKey` to any widget, so
    // `_captureAndBroadcastFrame()` always bails out and no frames are sent.
    // Remove `skip` once a RepaintBoundary(key: ...) wraps the dashboard.
    testWidgets('KNOWN GAP: Device A actually streams frames to a client',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await pumpUntilFound(tester, kIpText);

      final frames = <FramePacket>[];
      final client = WebSocketClientService()..onFrameReceived = frames.add;
      addTearDown(client.disconnect);
      expect(await client.connect('127.0.0.1:$kPort'), isTrue);

      await pumpUntil(tester, () => frames.isNotEmpty,
          timeout: const Duration(seconds: 8),
          reason: 'at least one frame from Device A');
      expect(frames.first.imageBytes, isNotEmpty);
      expect(frames.first.width, greaterThan(0));

      await leaveScreen(tester);
    }, skip: true);
  });

  // =========================================================================
  group('Device A -> Device B end to end', () {
    late WebSocketServerService host;

    setUp(() async {
      await waitForPortFree();
      host = WebSocketServerService();
      expect(await host.startServer(port: kPort), isTrue,
          reason: 'port $kPort must be free to run this test');
    });

    tearDown(() => host.stopServer());

    testWidgets('Device B screen connects and mirrors frames and touches',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);

      await connectDeviceB(tester, '127.0.0.1:$kPort');
      expect(find.text('Connected to Device A!'), findsOneWidget);
      expect(find.text('WEBSOCKET STREAM LIVE'), findsOneWidget);
      await pumpUntil(tester, () => host.clientCount == 1,
          reason: 'host to register the client');

      // A frame from the host appears on Device B.
      await host.broadcastFrame(FramePacket(
        imageBytes: kTinyPng,
        aspectRatio: 0.5,
        width: 540,
        height: 960,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));
      await pumpUntilFound(tester, find.textContaining('Resolution: 540x960'));
      expect(find.byType(Image), findsOneWidget);

      // A touch on the host shows up as an active touch on Device B...
      await host.broadcastGesture(makeGesture(PointerAction.down));
      await pumpUntilFound(tester, find.text('Active Touches: 1'));

      // ...and disappears on release.
      await host.broadcastGesture(makeGesture(PointerAction.up));
      await pumpUntilFound(tester, find.text('Active Touches: 0'));

      // Disconnecting from the UI is reflected on the host.
      await tester.tap(find.text('Disconnect'));
      await pumpUntilFound(tester, find.text('Connect'));
      await pumpUntil(tester, () => host.clientCount == 0,
          reason: 'host to drop the client');
    });

    testWidgets('Device B screen notices when the host stops', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');

      await host.stopServer();

      await pumpUntilFound(tester, find.text('Connect'));
      expect(find.text('Disconnect'), findsNothing);
      expect(find.text('Disconnected from host'), findsOneWidget);
      expect(find.text('WEBSOCKET STREAM LIVE'), findsNothing);
    });

    testWidgets('connected state before the first frame', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');

      expect(find.textContaining('Waiting for live screen frames'),
          findsOneWidget);
      expect(find.byIcon(Icons.wifi_tethering_rounded), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('WEBSOCKET STREAM LIVE'), findsOneWidget);
      expect(find.textContaining('FPS:'), findsOneWidget);
      expect(find.text('Active Touches: 0'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('Resolution:'), findsNothing);
      // Address box is locked while connected.
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    });

    testWidgets('accepts several ways of typing the host address',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);

      final inputs = <String>[
        '127.0.0.1:$kPort',
        '127.0.0.1', // default port 8080
        '  127.0.0.1:$kPort  ', // trimmed
        'ws://127.0.0.1:$kPort', // scheme stripped
        'http://127.0.0.1:$kPort',
        '127.0.0.1:notaport', // bad port falls back to 8080
      ];
      for (final input in inputs) {
        await connectDeviceB(tester, input);
        await pumpUntil(tester, () => host.clientCount == 1,
            reason: 'host to see client for "$input"');
        await disconnectDeviceB(tester);
        await pumpUntil(tester, () => host.clientCount == 0,
            reason: 'host to drop client for "$input"');
      }
    });

    testWidgets('frames replace each other and update the telemetry',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');

      await host.broadcastFrame(makeFrame(width: 540, height: 960));
      await pumpUntilFound(tester, find.textContaining('Resolution: 540x960'));

      await host.broadcastFrame(makeFrame(width: 1080, height: 2400));
      await pumpUntilFound(tester, find.textContaining('Resolution: 1080x2400'));
      expect(find.textContaining('Resolution: 540x960'), findsNothing);
      expect(find.byType(Image), findsOneWidget, reason: 'frames do not stack');
      expect(find.byType(LiveGestureOverlay), findsOneWidget);
    });

    testWidgets('latency is measured and clamped to 0..5000 ms',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');
      final now = DateTime.now().millisecondsSinceEpoch;

      await host.broadcastFrame(makeFrame(timestamp: now - 60000));
      await pumpUntilFound(tester, find.textContaining('Latency: 5000ms'));

      await host.broadcastFrame(
          makeFrame(timestamp: DateTime.now().millisecondsSinceEpoch + 60000));
      await pumpUntilFound(tester, find.textContaining('Latency: 0ms'));

      await host.broadcastFrame(
          makeFrame(timestamp: DateTime.now().millisecondsSinceEpoch - 400));
      await pumpUntil(tester, () {
        final v = latencyMs(tester);
        return v >= 400 && v < 3000;
      }, reason: 'latency of a ~400 ms old frame');
    });

    testWidgets('FPS counter reflects frames received', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');

      for (var i = 0; i < 6; i++) {
        await host.broadcastFrame(makeFrame());
        await tester.pump(const Duration(milliseconds: 50));
      }
      await pumpUntilFound(
        tester,
        find.byWidgetPredicate(
            (w) => w is Text && RegExp(r'FPS: [1-9]').hasMatch(w.data ?? '')),
        timeout: const Duration(seconds: 4),
      );
    });

    testWidgets('telemetry overlay can be hidden and shown', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');
      await host.broadcastFrame(makeFrame());
      await pumpUntilFound(tester, find.textContaining('Resolution:'));

      await tester.tap(find.byTooltip('Toggle Telemetry Overlay'));
      await tester.pump();
      expect(find.text('WEBSOCKET STREAM LIVE'), findsNothing);
      expect(find.textContaining('Resolution:'), findsNothing);
      expect(find.byType(Image), findsOneWidget, reason: 'stream keeps running');

      await tester.tap(find.byTooltip('Toggle Telemetry Overlay'));
      await tester.pump();
      expect(find.text('WEBSOCKET STREAM LIVE'), findsOneWidget);
      expect(find.textContaining('Resolution:'), findsOneWidget);
    });

    testWidgets('aspect-ratio menu changes how the frame is fitted',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');
      await host.broadcastFrame(makeFrame());
      await pumpUntilFound(tester, find.byType(Image));

      expect(currentFit(tester), BoxFit.contain);

      await chooseFit(tester, 'Fill Stretch (Fill)');
      expect(currentFit(tester), BoxFit.fill);

      await chooseFit(tester, 'Zoom Cover (Cover)');
      expect(currentFit(tester), BoxFit.cover);

      await chooseFit(tester, 'Fit Screen (Contain)');
      expect(currentFit(tester), BoxFit.contain);
    });

    testWidgets('multi-touch, move, scroll and cancel are tracked',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');
      await host.broadcastFrame(makeFrame());
      await pumpUntilFound(tester, find.textContaining('Resolution:'));

      await host.broadcastGesture(makeGesture(PointerAction.down, id: 1));
      await host.broadcastGesture(
          makeGesture(PointerAction.down, id: 2, x: 0.7, y: 0.2));
      await pumpUntilFound(tester, find.text('Active Touches: 2'));

      // Moving an existing pointer updates it instead of adding another.
      await host.broadcastGesture(
          makeGesture(PointerAction.move, id: 1, x: 0.5, y: 0.5));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('Active Touches: 2'), findsOneWidget);

      // Scroll events are shown as an indicator, not as a held touch.
      await host.broadcastGesture(
          makeGesture(PointerAction.scroll, id: 3, scrollDy: 120));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('Active Touches: 2'), findsOneWidget);

      await host.broadcastGesture(makeGesture(PointerAction.up, id: 1));
      await pumpUntilFound(tester, find.text('Active Touches: 1'));

      await host.broadcastGesture(makeGesture(PointerAction.cancel, id: 2));
      await pumpUntilFound(tester, find.text('Active Touches: 0'));
    });

    testWidgets('corrupt or unknown packets are ignored', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');

      host.broadcast('this is not json');
      host.broadcast('{"type":"frame","base64":"@@not-base64@@"}');
      host.broadcast('{"type":"frame"}'); // missing payload
      host.broadcast('{"type":"mystery"}');
      host.broadcast(jsonEncode(SystemHandshakePacket(
        deviceName: 'Test',
        deviceRole: 'broadcaster',
        screenWidth: 100,
        screenHeight: 200,
      ).toJson()));
      await pumpFor(tester, const Duration(milliseconds: 400));

      expect(find.text('Disconnect'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(tester.takeException(), isNull);

      // The stream still works afterwards.
      await host.broadcastFrame(makeFrame(width: 321, height: 654));
      await pumpUntilFound(tester, find.textContaining('Resolution: 321x654'));
    });

    testWidgets('disconnect -> reconnect resumes the stream', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');
      await host.broadcastFrame(makeFrame(width: 100, height: 200));
      await pumpUntilFound(tester, find.textContaining('Resolution: 100x200'));

      await disconnectDeviceB(tester);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('WEBSOCKET STREAM LIVE'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await pumpUntil(tester, () => host.clientCount == 0,
          reason: 'host to drop the client');

      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.text('Disconnect'));
      await pumpUntil(tester, () => host.clientCount == 1,
          reason: 'host to see the reconnect');

      await host.broadcastFrame(makeFrame(width: 300, height: 400));
      await pumpUntilFound(tester, find.textContaining('Resolution: 300x400'));
    });

    testWidgets('host restarts -> Device B can reconnect', (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');

      await host.stopServer();
      await pumpUntilFound(tester, find.text('Connect'));

      expect(await host.startServer(port: kPort), isTrue);
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.text('Disconnect'));
      await pumpUntil(tester, () => host.clientCount == 1,
          reason: 'host to see the client again');

      await host.broadcastFrame(makeFrame(width: 222, height: 333));
      await pumpUntilFound(tester, find.textContaining('Resolution: 222x333'));
    });

    testWidgets('a second client receives the same frames as Device B',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');

      final extra = <FramePacket>[];
      final other = WebSocketClientService()..onFrameReceived = extra.add;
      addTearDown(other.disconnect);
      expect(await other.connect('127.0.0.1:$kPort'), isTrue);
      await pumpUntil(tester, () => host.clientCount == 2,
          reason: 'both clients registered');

      await host.broadcastFrame(makeFrame(width: 411, height: 822));
      await pumpUntilFound(tester, find.textContaining('Resolution: 411x822'));
      await pumpUntil(tester, () => extra.isNotEmpty,
          reason: 'second client to receive the frame');
      expect(extra.first.width, 411);
    });

    // KNOWN GAP (suspected): `_activeGestures` is never cleared on disconnect,
    // so a touch that was down when the link dropped is still counted after
    // reconnecting. Remove `skip` once Device B clears it in its status callback.
    testWidgets('KNOWN GAP: held touches are cleared when the link drops',
        (tester) async {
      await launchApp(tester);
      await openDeviceB(tester);
      await connectDeviceB(tester, '127.0.0.1:$kPort');
      await host.broadcastGesture(makeGesture(PointerAction.down, id: 7));
      await pumpUntilFound(tester, find.text('Active Touches: 1'));

      await disconnectDeviceB(tester);
      await tester.tap(find.text('Connect'));
      await pumpUntilFound(tester, find.text('Disconnect'));

      expect(find.text('Active Touches: 0'), findsOneWidget);
    }, skip: true);
  });

  // =========================================================================
  // Service layer: no widgets, real sockets.
  // =========================================================================
  group('WebSocketServerService / WebSocketClientService', () {
    late WebSocketServerService host;

    setUp(() async {
      await waitForPortFree();
      host = WebSocketServerService();
    });

    tearDown(() => host.stopServer());

    test('serves the built-in web viewer over plain HTTP', () async {
      expect(await host.startServer(port: kPort), isTrue);
      expect(host.isHosting, isTrue);
      expect(host.port, kPort);

      final http = HttpClient();
      addTearDown(http.close);
      final req = await http.getUrl(Uri.parse('http://127.0.0.1:$kPort/'));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'text/html');
      expect(body, contains('<html'));
      expect(body, contains('new WebSocket('));
      expect(body, contains('Device A Live Screen'));
    });

    test('a second server cannot take a busy port; it can after stop',
        () async {
      expect(await host.startServer(port: kPort), isTrue);

      final second = WebSocketServerService();
      expect(await second.startServer(port: kPort), isFalse);
      expect(second.isHosting, isFalse);

      await host.stopServer();
      expect(host.isHosting, isFalse);
      expect(await second.startServer(port: kPort), isTrue);
      await second.stopServer();
    });

    test('broadcasting with no clients or no server is a harmless no-op',
        () async {
      await host.broadcastFrame(makeFrame()); // not started
      await host.broadcastGesture(makeGesture(PointerAction.down));
      expect(await host.startServer(port: kPort), isTrue);
      await host.broadcastFrame(makeFrame()); // started, no clients
      await host.broadcastGesture(makeGesture(PointerAction.down));
      expect(host.clientCount, 0);
    });

    test('client-count callback reports 1, 2, 1, 0', () async {
      final counts = <int>[];
      host.onClientCountChanged = counts.add;
      expect(await host.startServer(port: kPort), isTrue);

      final a = WebSocketClientService();
      final b = WebSocketClientService();
      addTearDown(a.disconnect);
      addTearDown(b.disconnect);

      expect(await a.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => counts.length == 1, reason: 'first join');
      expect(await b.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => counts.length == 2, reason: 'second join');
      await a.disconnect();
      await waitFor(() => counts.length == 3, reason: 'first leave');
      await b.disconnect();
      await waitFor(() => counts.length == 4, reason: 'second leave');

      expect(counts, [1, 2, 1, 0]);
    });

    test('logs server lifecycle events', () async {
      final logs = <String>[];
      host.onLog = logs.add;
      expect(await host.startServer(port: kPort), isTrue);
      final c = WebSocketClientService();
      expect(await c.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => host.clientCount == 1);
      await c.disconnect();
      await waitFor(() => host.clientCount == 0);
      await host.stopServer();

      expect(logs.any((l) => l.contains('Server started')), isTrue);
      expect(logs.any((l) => l.contains('Client connected')), isTrue);
      expect(logs.any((l) => l.contains('Client disconnected')), isTrue);
      expect(logs.any((l) => l.contains('Server stopped')), isTrue);
    });

    test('frames reach every client intact (incl. a 400 KB payload)',
        () async {
      expect(await host.startServer(port: kPort), isTrue);
      final got1 = <FramePacket>[];
      final got2 = <FramePacket>[];
      final c1 = WebSocketClientService()..onFrameReceived = got1.add;
      final c2 = WebSocketClientService()..onFrameReceived = got2.add;
      addTearDown(c1.disconnect);
      addTearDown(c2.disconnect);
      expect(await c1.connect('127.0.0.1:$kPort'), isTrue);
      expect(await c2.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => host.clientCount == 2);

      final big = Uint8List.fromList(
          List<int>.generate(400 * 1024, (i) => (i * 7) % 251));
      await host.broadcastFrame(
          makeFrame(width: 720, height: 1280, bytes: big, timestamp: 42));
      await waitFor(() => got1.isNotEmpty && got2.isNotEmpty,
          reason: 'both clients to receive the big frame');

      for (final f in [got1.first, got2.first]) {
        expect(f.width, 720);
        expect(f.height, 1280);
        expect(f.timestamp, 42);
        expect(listEquals(f.imageBytes, big), isTrue);
      }
    });

    test('a burst of 30 frames arrives complete and in order', () async {
      expect(await host.startServer(port: kPort), isTrue);
      final got = <int>[];
      final c = WebSocketClientService()
        ..onFrameReceived = (f) => got.add(f.timestamp);
      addTearDown(c.disconnect);
      expect(await c.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => host.clientCount == 1);

      for (var i = 0; i < 30; i++) {
        await host.broadcastFrame(makeFrame(timestamp: i));
      }
      await waitFor(() => got.length == 30, reason: 'all 30 frames');
      expect(got, List<int>.generate(30, (i) => i));
    });

    test('gestures round-trip host -> client with every field', () async {
      expect(await host.startServer(port: kPort), isTrue);
      final got = <GesturePacket>[];
      final c = WebSocketClientService()..onGestureReceived = got.add;
      addTearDown(c.disconnect);
      expect(await c.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => host.clientCount == 1);

      await host.broadcastGesture(GesturePacket(
        action: PointerAction.scroll,
        pointerId: 9,
        normalizedX: 0.25,
        normalizedY: 0.75,
        scrollDeltaX: -3.5,
        scrollDeltaY: 42,
        timestamp: 1234,
        deviceWidth: 411,
        deviceHeight: 914,
      ));
      await waitFor(() => got.isNotEmpty);

      final g = got.single;
      expect(g.action, PointerAction.scroll);
      expect(g.pointerId, 9);
      expect(g.normalizedX, 0.25);
      expect(g.normalizedY, 0.75);
      expect(g.scrollDeltaX, -3.5);
      expect(g.scrollDeltaY, 42);
      expect(g.timestamp, 1234);
      expect(g.deviceWidth, 411);
      expect(g.deviceHeight, 914);
    });

    test('gestures flow client -> host', () async {
      final got = <GesturePacket>[];
      host.onGestureReceived = got.add;
      expect(await host.startServer(port: kPort), isTrue);
      final c = WebSocketClientService();
      addTearDown(c.disconnect);
      expect(await c.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => host.clientCount == 1);

      c.sendGesture(makeGesture(PointerAction.down, id: 4, x: 0.1, y: 0.9));
      c.sendGesture(makeGesture(PointerAction.up, id: 4, x: 0.1, y: 0.9));
      await waitFor(() => got.length == 2);

      expect(got.map((g) => g.action), [PointerAction.down, PointerAction.up]);
      expect(got.first.pointerId, 4);
      expect(got.first.normalizedX, 0.1);
      expect(got.first.normalizedY, 0.9);
    });

    test('host ignores garbage from a raw socket and keeps serving',
        () async {
      final got = <GesturePacket>[];
      host.onGestureReceived = got.add;
      expect(await host.startServer(port: kPort), isTrue);

      final raw = await WebSocket.connect('ws://127.0.0.1:$kPort');
      addTearDown(() => raw.close());
      await waitFor(() => host.clientCount == 1);

      raw
        ..add('not json')
        ..add('{"type":"gesture"') // truncated
        ..add(jsonEncode({'type': 'unknown'}))
        ..add(Uint8List.fromList([1, 2, 3])) // binary is ignored
        ..add(jsonEncode(makeGesture(PointerAction.down, id: 5).toJson()));
      await waitFor(() => got.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(got.length, 1);
      expect(got.single.pointerId, 5);
      expect(host.isHosting, isTrue);
      expect(host.clientCount, 1);
    });

    test('stopping the host notifies clients and drops the count', () async {
      expect(await host.startServer(port: kPort), isTrue);
      final statuses = <String>[];
      final c = WebSocketClientService()
        ..onStatusChanged = (ok, s) => statuses.add(s);
      expect(await c.connect('127.0.0.1:$kPort'), isTrue);
      await waitFor(() => host.clientCount == 1);

      await host.stopServer();
      await waitFor(() => !c.isConnected, reason: 'client to notice');

      expect(statuses.last, 'Disconnected from host');
      expect(host.clientCount, 0);
      expect(host.isHosting, isFalse);
    });

    test('rapid connect/disconnect cycles leave no ghost clients', () async {
      expect(await host.startServer(port: kPort), isTrue);
      for (var i = 0; i < 8; i++) {
        final c = WebSocketClientService();
        expect(await c.connect('127.0.0.1:$kPort'), isTrue, reason: 'cycle $i');
        await c.disconnect();
      }
      await waitFor(() => host.clientCount == 0, reason: 'all clients gone');
    });

    test('client rejects empty and unfinished addresses', () async {
      final statuses = <String>[];
      final c = WebSocketClientService()
        ..onStatusChanged = (ok, s) => statuses.add(s);

      for (final bad in ['', '   ', '192.168.1.']) {
        expect(await c.connect(bad), isFalse, reason: 'input "$bad"');
        expect(c.isConnected, isFalse);
        expect(statuses.last, 'Please enter a valid IP address');
      }
    });

    test('client reports failure for an unreachable host', () async {
      final statuses = <String>[];
      final c = WebSocketClientService()
        ..onStatusChanged = (ok, s) => statuses.add(s);

      expect(await c.connect('127.0.0.1:9'), isFalse);
      expect(c.isConnected, isFalse);
      expect(statuses.first, 'Connecting to ws://127.0.0.1:9...');
      expect(statuses.last, startsWith('Connection failed'));
    });

    test('client API is safe to misuse', () async {
      final c = WebSocketClientService();
      c.sendGesture(makeGesture(PointerAction.down)); // not connected
      await c.disconnect(); // not connected
      await c.disconnect(); // twice
      expect(c.isConnected, isFalse);
    });
  });

  // =========================================================================
  // Wire format
  // =========================================================================
  group('Protocol models', () {
    test('GesturePacket JSON round-trips for every PointerAction', () {
      for (final action in PointerAction.values) {
        final src = GesturePacket(
          action: action,
          pointerId: 3,
          normalizedX: 0.123,
          normalizedY: 0.987,
          scrollDeltaX: 1.5,
          scrollDeltaY: -2.5,
          timestamp: 99,
          deviceWidth: 360,
          deviceHeight: 800,
        );
        final json = jsonDecode(jsonEncode(src.toJson())) as Map<String, dynamic>;
        expect(json['type'], 'gesture');
        final back = GesturePacket.fromJson(json);

        expect(back.action, action);
        expect(back.pointerId, 3);
        expect(back.normalizedX, 0.123);
        expect(back.normalizedY, 0.987);
        expect(back.scrollDeltaX, 1.5);
        expect(back.scrollDeltaY, -2.5);
        expect(back.timestamp, 99);
        expect(back.deviceWidth, 360);
        expect(back.deviceHeight, 800);
      }
    });

    test('GesturePacket.fromJson tolerates missing / unknown fields', () {
      final g = GesturePacket.fromJson({'type': 'gesture', 'action': 'bogus'});
      expect(g.action, PointerAction.move);
      expect(g.pointerId, 0);
      expect(g.normalizedX, 0.0);
      expect(g.normalizedY, 0.0);
      expect(g.scrollDeltaX, 0.0);
      expect(g.deviceWidth, 1.0);
      expect(g.deviceHeight, 1.0);

      // ints are accepted where doubles are expected
      final i = GesturePacket.fromJson({'normalizedX': 1, 'normalizedY': 0});
      expect(i.normalizedX, 1.0);
    });

    test('FramePacket base64 JSON round-trips bytes and metadata', () {
      final src = FramePacket(
        imageBytes: kTinyPng,
        aspectRatio: 0.45,
        width: 450,
        height: 1000,
        timestamp: 777,
        currentFps: 12.5,
      );
      final json = jsonDecode(src.toBase64Json()) as Map<String, dynamic>;
      expect(json['type'], 'frame');
      expect(json['bytesLength'], kTinyPng.length);

      final back = FramePacket.fromBase64Json(json);
      expect(listEquals(back.imageBytes, kTinyPng), isTrue);
      expect(back.aspectRatio, 0.45);
      expect(back.width, 450);
      expect(back.height, 1000);
      expect(back.timestamp, 777);
      expect(back.currentFps, 12.5);
    });

    test('FramePacket.fromBase64Json applies defaults', () {
      final f = FramePacket.fromBase64Json({'base64': base64Encode(kTinyPng)});
      expect(f.aspectRatio, 0.5);
      expect(f.width, 1080);
      expect(f.height, 1920);
      expect(f.currentFps, 30.0);
    });

    test('FramePacket.fromBase64Json rejects a missing or invalid payload', () {
      expect(() => FramePacket.fromBase64Json({}), throwsA(anything));
      expect(() => FramePacket.fromBase64Json({'base64': '@@@'}),
          throwsFormatException);
    });

    test('SystemHandshakePacket round-trips and has defaults', () {
      final src = SystemHandshakePacket(
        deviceName: 'Pixel',
        deviceRole: 'receiver',
        screenWidth: 411,
        screenHeight: 914,
      );
      final json = src.toJson();
      expect(json['type'], 'handshake');
      final back = SystemHandshakePacket.fromJson(json);
      expect(back.deviceName, 'Pixel');
      expect(back.deviceRole, 'receiver');
      expect(back.screenWidth, 411);
      expect(back.screenHeight, 914);

      final d = SystemHandshakePacket.fromJson({});
      expect(d.deviceName, 'Unknown Device');
      expect(d.deviceRole, 'broadcaster');
      expect(d.screenWidth, 1080.0);
      expect(d.screenHeight, 1920.0);
    });
  });

  // =========================================================================
  // Museum Map - detailed suite
  // =========================================================================


  group('Initial state', () {
    testWidgets('shows a chip and a pin for every POI, nothing selected',
        (tester) async {
      await pumpMap(tester);

      expect(chip('All Places'), findsOneWidget);
      for (final p in pois) {
        expect(chip(p.tag), findsOneWidget, reason: 'chip ${p.tag}');
        expect(pin(p.tag), findsOneWidget, reason: 'pin ${p.tag}');
      }
      expectOnlySelected(tester, null);
      expect(find.text('Read More'), findsNothing);
      expect(find.text('Overview'), findsNothing);
      expect(scaleOf(tester), closeTo(1.0, 1e-6));
    });

    testWidgets('floor-plan asset is bundled (fallback not shown)',
        (tester) async {
      await pumpMap(tester);
      // The fallback only renders when Image.asset fails to load.
      expect(find.text('Museum Floor Map'), findsNothing);
      expect(
        find.descendant(
            of: find.byType(InteractiveViewer), matching: find.byType(Image)),
        findsOneWidget,
      );
    });

    testWidgets('map keeps the 675:1200 aspect ratio and pins sit on it',
        (tester) async {
      await pumpMap(tester);
      final img = find.descendant(
          of: find.byType(InteractiveViewer), matching: find.byType(Image));
      final size = tester.getSize(img);
      expect(size.width / size.height, closeTo(675 / 1200, 0.01));

      final imgRect = tester.getRect(img);
      for (final p in pois) {
        expect(imgRect.contains(tester.getCenter(pin(p.tag))), isTrue,
            reason: '${p.tag} pin should be inside the map image');
      }
    });

    testWidgets('pins are laid out according to their dx / dy', (tester) async {
      await pumpMap(tester);
      final c = {for (final p in pois) p.id: tester.getCenter(pin(p.tag))};
      for (final a in pois) {
        for (final b in pois) {
          if (b.dy - a.dy > 0.1) {
            expect(c[b.id]!.dy, greaterThan(c[a.id]!.dy),
                reason: '${b.tag} should be below ${a.tag}');
          }
          // Wider threshold: pin labels differ in width.
          if (b.dx - a.dx > 0.2) {
            expect(c[b.id]!.dx, greaterThan(c[a.id]!.dx),
                reason: '${b.tag} should be right of ${a.tag}');
          }
        }
      }
    });

    testWidgets('floating buttons are present', (tester) async {
      await pumpMap(tester);
      expect(find.byTooltip('Reset Map View'), findsOneWidget);
      expect(find.byTooltip('Zoom In'), findsOneWidget);
    });
  });

  group('Selecting a POI with its chip', () {
    for (final poi in pois) {
      testWidgets('${poi.tag}: callout, highlight, pin and zoom',
          (tester) async {
        await pumpMap(tester);
        await selectViaChip(tester, poi);

        expectCalloutFor(tester, poi);
        expectOnlySelected(tester, poi);
        expect(scaleOf(tester),
            closeTo(expectedSelectScale(mapRect(tester).width), 0.02));

        // Callout card stays inside the screen, 14px from the edges.
        final area = mapRect(tester);
        final nameRect = onScreenRect(tester, find.text(poi.name));
        expect(nameRect, isNotNull);
        expect(nameRect!.left, greaterThanOrEqualTo(area.left + 14));
        expect(nameRect.right, lessThanOrEqualTo(area.right - 14));
      });
    }

    testWidgets('switching from one POI to another moves the selection',
        (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[0]);
      expectOnlySelected(tester, pois[0]);

      await selectViaChip(tester, pois[1]);
      expectCalloutFor(tester, pois[1]);
      expectOnlySelected(tester, pois[1]);
      // Old callout content is gone.
      expect(find.text(pois[0].shortDescription), findsNothing);
    });

    testWidgets('selecting every POI in turn never throws', (tester) async {
      await pumpMap(tester);
      for (final p in [...pois, ...pois.reversed]) {
        await selectViaChip(tester, p);
        expectOnlySelected(tester, p);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Selecting a POI by tapping its pin', () {
    for (final poi in pois) {
      testWidgets('${poi.tag} pin', (tester) async {
        await pumpMap(tester);
        await selectViaPin(tester, poi);

        expectCalloutFor(tester, poi);
        expectOnlySelected(tester, poi);
        expect(scaleOf(tester), greaterThan(1.5));
      });
    }

    testWidgets('pin and chip selection give identical zoom', (tester) async {
      await pumpMap(tester);
      await selectViaPin(tester, pois[1]);
      final viaPin = matrixOf(tester).storage.toList();

      await resetViaChip(tester);
      await selectViaChip(tester, pois[1]);
      final viaChip = matrixOf(tester).storage.toList();

      for (var i = 0; i < 16; i++) {
        expect(viaChip[i], closeTo(viaPin[i], 0.5), reason: 'matrix[$i]');
      }
    });
  });

  group('Dismissing and resetting', () {
    testWidgets('close (x) on the callout deselects the POI', (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[1]);

      // The callout is built before the (off-screen) panel, so .first is
      // the callout's close button.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Read More'), findsNothing);
      expect(find.text('Overview'), findsNothing);
      expectOnlySelected(tester, null);
    });

    testWidgets('"All Places" chip deselects and zooms back out',
        (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[2]);
      expect(scaleOf(tester), greaterThan(1.5));

      await resetViaChip(tester);

      expect(find.text('Read More'), findsNothing);
      expectOnlySelected(tester, null);
      expect(scaleOf(tester), closeTo(1.0, 0.01));
      expect(matrixOf(tester).storage[12], closeTo(0, 1.0));
      expect(matrixOf(tester).storage[13], closeTo(0, 1.0));
    });

    testWidgets('reset FAB behaves like "All Places"', (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[0]);

      await tester.tap(find.byTooltip('Reset Map View'));
      await tester.pumpAndSettle();

      expectOnlySelected(tester, null);
      expect(scaleOf(tester), closeTo(1.0, 0.01));
      expect(find.text('Read More'), findsNothing);
    });

    testWidgets('reset also works from the details panel state',
        (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[0]);
      await openPanel(tester);
      await closePanel(tester);
      await tester.tap(find.byTooltip('Reset Map View'));
      await tester.pumpAndSettle();

      expectOnlySelected(tester, null);
      expect(panelVisible(tester), isFalse);
    });
  });

  group('Details side panel', () {
    for (final poi in pois) {
      testWidgets('${poi.tag}: Read More shows full details', (tester) async {
        await pumpMap(tester);
        await selectViaChip(tester, poi);
        // Panel content is in the tree but off-screen until opened.
        expect(panelVisible(tester), isFalse);

        await openPanel(tester);

        expectPanelFor(tester, poi);
        expectOnlySelected(tester, poi);
      });
    }

    testWidgets('panel has the documented width and docks to the right',
        (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[0]);
      await openPanel(tester);

      final area = mapRect(tester);
      final panelLeft = area.right - expectedPanelWidth(area.width);
      expect(tester.getTopLeft(find.text('Overview')).dx,
          greaterThanOrEqualTo(panelLeft - 1));
      expect(tester.getTopRight(find.text('Overview')).dx,
          lessThanOrEqualTo(area.right + 1));
    });

    testWidgets('opening the panel re-centres the pin to the left',
        (tester) async {
      await pumpMap(tester);
      final poi = pois[1];
      await selectViaChip(tester, poi);
      final xBefore = tester.getCenter(pin(poi.tag)).dx;

      await openPanel(tester);
      final xOpen = tester.getCenter(pin(poi.tag)).dx;
      expect(xOpen, lessThan(xBefore),
          reason: 'camera should shift the pin into the uncovered area');

      await closePanel(tester);
      final xClosed = tester.getCenter(pin(poi.tag)).dx;
      expect(xClosed, closeTo(xBefore, 2.0),
          reason: 'closing the panel restores the previous framing');
    });

    testWidgets('close (x) hides the panel and brings the callout back',
        (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[2]);
      await openPanel(tester);
      expect(panelVisible(tester), isTrue);

      await closePanel(tester);

      expect(panelVisible(tester), isFalse);
      expectCalloutFor(tester, pois[2]);
      expectOnlySelected(tester, pois[2]); // still selected
    });

    testWidgets('Directions and bookmark buttons show feedback',
        (tester) async {
      await pumpMap(tester);
      final poi = pois[1];
      await selectViaChip(tester, poi);
      await openPanel(tester);

      await tester.ensureVisible(find.text('Directions'));
      await tester.tap(find.text('Directions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Navigating to ${poi.name}...'), findsWidgets);
      clearSnackBars(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byIcon(Icons.bookmark_add_rounded));
      await tester.tap(find.byIcon(Icons.bookmark_add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Saved ${poi.name} to favorites!'), findsWidgets);
    });

    testWidgets('panel content scrolls to the last highlight', (tester) async {
      await pumpMap(tester, size: const Size(360, 520)); // short screen
      await selectViaChip(tester, pois[0]);
      await openPanel(tester);

      final last = find.text(pois[0].highlights.last);
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(onScreen(tester, last), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('re-opening after close works repeatedly', (tester) async {
      await pumpMap(tester);
      await selectViaChip(tester, pois[0]);
      for (var i = 0; i < 3; i++) {
        await openPanel(tester);
        expect(panelVisible(tester), isTrue, reason: 'open #$i');
        await closePanel(tester);
        expect(panelVisible(tester), isFalse, reason: 'close #$i');
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('Zoom and pan', () {
    testWidgets('zoom-in FAB multiplies by 1.4 and stops at ~3.84',
        (tester) async {
      await pumpMap(tester);
      for (final expected in [1.4, 1.96, 2.744, 3.8416]) {
        await tester.tap(find.byTooltip('Zoom In'));
        await tester.pumpAndSettle();
        expect(scaleOf(tester), closeTo(expected, 0.01));
      }
      // Above 3.8 the FAB refuses to zoom further.
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();
      expect(scaleOf(tester), closeTo(3.8416, 0.01));
    });

    testWidgets('reset FAB returns from a manual zoom', (tester) async {
      await pumpMap(tester);
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();
      expect(scaleOf(tester), greaterThan(1.9));

      await tester.tap(find.byTooltip('Reset Map View'));
      await tester.pumpAndSettle();
      expect(scaleOf(tester), closeTo(1.0, 0.01));
    });

    testWidgets('dragging the zoomed map pans it', (tester) async {
      await pumpMap(tester);
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Zoom In'));
      await tester.pumpAndSettle();
      final before = matrixOf(tester).storage.toList();

      await tester.drag(
          find.byType(InteractiveViewer), const Offset(-100, -80));
      await tester.pumpAndSettle();
      final after = matrixOf(tester).storage.toList();

      expect(after[12], lessThan(before[12] - 50), reason: 'x translation');
      expect(after[13], lessThan(before[13] - 40), reason: 'y translation');
      expect(after[0], closeTo(before[0], 1e-6), reason: 'scale unchanged');
    });

    testWidgets('pinch-out zooms in, pinch-in cannot go below 1x',
        (tester) async {
      await pumpMap(tester);
      final c = tester.getCenter(find.byType(InteractiveViewer));

      // Pinch out.
      var g1 = await tester.startGesture(c - const Offset(30, 0), pointer: 1);
      var g2 = await tester.startGesture(c + const Offset(30, 0), pointer: 2);
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await g1.moveBy(const Offset(-10, 0));
        await g2.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
      expect(scaleOf(tester), greaterThan(2.0));
      expect(scaleOf(tester), lessThanOrEqualTo(4.0 + 1e-6));

      // Reset, then pinch in from 1x: minScale is 1.0.
      await tester.tap(find.byTooltip('Reset Map View'));
      await tester.pumpAndSettle();
      g1 = await tester.startGesture(c - const Offset(100, 0), pointer: 3);
      g2 = await tester.startGesture(c + const Offset(100, 0), pointer: 4);
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await g1.moveBy(const Offset(12, 0));
        await g2.moveBy(const Offset(-12, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();
      expect(scaleOf(tester), closeTo(1.0, 0.01));
    });

    testWidgets('callout follows its pin when the map moves', (tester) async {
      await pumpMap(tester);
      final poi = pois[0];
      await selectViaChip(tester, poi);

      final pinBefore = tester.getCenter(pin(poi.tag));
      final cardBefore = tester.getCenter(find.text('Read More'));

      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!;
      controller.value = Matrix4.translationValues(0, -40, 0) * controller.value;
      await tester.pump();

      final pinAfter = tester.getCenter(pin(poi.tag));
      final cardAfter = tester.getCenter(find.text('Read More'));
      expect(pinAfter.dy, closeTo(pinBefore.dy - 40, 1.0));
      expect(cardAfter.dy, closeTo(cardBefore.dy - 40, 1.0),
          reason: 'info window is anchored to the pin tip');
    });
  });

  group('Responsive layouts', () {
    const sizes = <String, Size>{
      'small phone 320x568': Size(320, 568),
      'phone 390x844': Size(390, 844),
      'wide phone 540x960': Size(540, 960),
      'tablet 820x1180': Size(820, 1180),
    };

    sizes.forEach((label, size) {
      testWidgets('$label: every POI callout + panel fits', (tester) async {
        await pumpMap(tester, size: size);
        final area = mapRect(tester);

        for (final poi in pois) {
          await selectViaChip(tester, poi);
          expectCalloutFor(tester, poi);
          expect(scaleOf(tester), closeTo(expectedSelectScale(area.width), 0.02),
              reason: '${poi.tag} zoom at $label');

          final readMore = tester.getRect(find.text('Read More'));
          expect(area.contains(readMore.center), isTrue,
              reason: 'Read More reachable for ${poi.tag}');
          expect(readMore.right, lessThanOrEqualTo(area.right));

          await openPanel(tester);
          expectPanelFor(tester, poi);
          final left = area.right - expectedPanelWidth(area.width);
          expect(tester.getTopLeft(find.text('Overview')).dx,
              greaterThanOrEqualTo(left - 1));

          if (area.width >= 600) {
            // Tablet: pin must remain visible beside the 380px panel.
            expect(tester.getCenter(pin(poi.tag)).dx, lessThan(left),
                reason: '${poi.tag} pin should not be hidden by the panel');
          }

          await closePanel(tester);
          await resetViaChip(tester);
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('short landscape screen does not overflow', (tester) async {
      await pumpMap(tester, size: const Size(800, 400));
      for (final poi in pois) {
        await selectViaChip(tester, poi);
        expect(onScreen(tester, find.text(poi.name)), isTrue);
        await resetViaChip(tester);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('chip bar scrolls to reach the last chip on a narrow phone',
        (tester) async {
      await pumpMap(tester, size: const Size(320, 640));
      final last = chip(pois.last.tag);
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expectOnlySelected(tester, pois.last);
    });
  });

  // -------------------------------------------------------------------------
  // The same map, reached through the real app + Device A screen.
  // -------------------------------------------------------------------------
  group('Museum map inside Device A', () {
    setUp(() async => waitForPortFree());

    testWidgets('tab switch shows the map and hides the dashboard',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      expect(find.text('Interactive UI Controls'), findsOneWidget);
      expect(find.byType(MuseumMapView), findsNothing); // IndexedStack: off-stage

      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();

      expect(find.byType(MuseumMapView), findsOneWidget);
      expect(find.text('Interactive UI Controls'), findsNothing);
      expectOnlySelected(tester, null);
      expect(find.text('Museum Floor Map'), findsNothing);

      await leaveScreen(tester);
    });

    testWidgets('full tour: every POI, details, feedback, reset',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();

      for (final poi in pois) {
        await selectViaChip(tester, poi);
        expectCalloutFor(tester, poi);
        expectOnlySelected(tester, poi);

        await openPanel(tester);
        expectPanelFor(tester, poi);

        await tester.ensureVisible(find.text('Directions'));
        await tester.tap(find.text('Directions'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Navigating to ${poi.name}...'), findsWidgets);
        clearSnackBars(tester);
        await tester.pumpAndSettle();

        await closePanel(tester);
        expectCalloutFor(tester, poi);
      }

      await resetViaChip(tester);
      expectOnlySelected(tester, null);
      expect(scaleOf(tester), closeTo(1.0, 0.01));
      expect(tester.takeException(), isNull);

      await leaveScreen(tester);
    });

    testWidgets('selection and zoom survive switching tabs', (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();

      final poi = pois[1];
      await selectViaChip(tester, poi);
      final scaleBefore = scaleOf(tester);

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();
      expect(find.byType(MuseumMapView), findsNothing);
      expect(find.text('Interactive UI Controls'), findsOneWidget);

      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();

      expectCalloutFor(tester, poi);
      expectOnlySelected(tester, poi);
      expect(scaleOf(tester), closeTo(scaleBefore, 0.01));

      await leaveScreen(tester);
    });

    testWidgets('leaving Device A and coming back starts with a fresh map',
        (tester) async {
      await launchApp(tester);
      await openDeviceA(tester);
      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();
      await selectViaChip(tester, pois[0]);
      await leaveScreen(tester);
      await waitForPortFree();

      await openDeviceA(tester);
      await tester.tap(find.text('Museum Map'));
      await tester.pumpAndSettle();
      expectOnlySelected(tester, null);
      expect(scaleOf(tester), closeTo(1.0, 1e-6));

      await leaveScreen(tester);
    });
  });
}