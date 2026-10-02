import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/models/mirror_protocol.dart';
import 'package:rndscreeningap/widgets/gesture_overlay_painter.dart';

GesturePacket _gesture({
  PointerAction action = PointerAction.move,
  int id = 1,
  double x = 0.5,
  double y = 0.5,
  double dx = 0,
  double dy = 0,
  int? timestamp,
}) =>
    GesturePacket(
      action: action,
      pointerId: id,
      normalizedX: x,
      normalizedY: y,
      scrollDeltaX: dx,
      scrollDeltaY: dy,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );

Future<void> _pumpOverlay(
  WidgetTester tester, {
  Map<int, GesturePacket> gestures = const {},
  GesturePacket? scroll,
  bool ripples = true,
  bool labels = true,
}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 300,
        height: 600,
        child: LiveGestureOverlay(
          activeGestures: gestures,
          latestScroll: scroll,
          canvasSize: const Size(300, 600),
          showRipples: ripples,
          showLabels: labels,
        ),
      ),
    ),
  );
}

Finder get _overlayPaint => find.descendant(
      of: find.byType(LiveGestureOverlay),
      matching: find.byType(CustomPaint),
    );

void paintOnce(GesturePainter painter, [Size size = const Size(300, 600)]) {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  recorder.endRecording();
}

void main() {
  group('LiveGestureOverlay', () {
    testWidgets('builds a GesturePainter wired to its inputs', (tester) async {
      final gestures = {1: _gesture(id: 1)};
      final scroll = _gesture(action: PointerAction.scroll, dy: 10);

      await _pumpOverlay(tester,
          gestures: gestures, scroll: scroll, ripples: false, labels: false);

      final painter =
          tester.widget<CustomPaint>(_overlayPaint).painter as GesturePainter;
      expect(painter.gestures, same(gestures));
      expect(painter.latestScroll, same(scroll));
      expect(painter.showRipples, isFalse);
      expect(painter.showLabels, isFalse);
    });

    testWidgets('animates: the animation value advances between frames',
        (tester) async {
      await _pumpOverlay(tester, gestures: {1: _gesture()});
      final first =
          (tester.widget<CustomPaint>(_overlayPaint).painter as GesturePainter)
              .animValue;

      await tester.pump(const Duration(milliseconds: 400));
      final second =
          (tester.widget<CustomPaint>(_overlayPaint).painter as GesturePainter)
              .animValue;

      expect(second, isNot(first));
    });

    testWidgets('paints nothing when there are no gestures', (tester) async {
      await _pumpOverlay(tester);
      expect(tester.renderObject(_overlayPaint), paintsNothing);
    });

    testWidgets('paints circles for an active touch', (tester) async {
      await _pumpOverlay(tester, gestures: {1: _gesture(action: PointerAction.down)});
      expect(tester.renderObject(_overlayPaint), paints..circle());
    });

    testWidgets('does not paint touches whose action is up or cancel',
        (tester) async {
      await _pumpOverlay(tester, gestures: {
        1: _gesture(id: 1, action: PointerAction.up),
        2: _gesture(id: 2, action: PointerAction.cancel),
      });
      expect(tester.renderObject(_overlayPaint), paintsNothing);
    });

    testWidgets('paints a fresh scroll indicator', (tester) async {
      await _pumpOverlay(
        tester,
        scroll: _gesture(action: PointerAction.scroll, dy: 30),
      );
      expect(tester.renderObject(_overlayPaint), paints..line());
    });

    testWidgets('does not paint a scroll indicator older than 800 ms',
        (tester) async {
      final stale = DateTime.now().millisecondsSinceEpoch - 5000;
      await _pumpOverlay(
        tester,
        scroll: _gesture(action: PointerAction.scroll, dy: 30, timestamp: stale),
      );
      expect(tester.renderObject(_overlayPaint), paintsNothing);
    });
  });

  group('GesturePainter', () {
    GesturePainter make({
      Map<int, GesturePacket>? gestures,
      GesturePacket? scroll,
      bool ripples = true,
      bool labels = true,
    }) =>
        GesturePainter(
          gestures: gestures ?? const {},
          latestScroll: scroll,
          animValue: 0.5,
          showRipples: ripples,
          showLabels: labels,
        );

    testWidgets('shouldRepaint is always true (animated overlay)', (tester) async {
      expect(make().shouldRepaint(make()), isTrue);
    });

    testWidgets('paints every combination of options without throwing',
        (tester) async {
      for (final ripples in [true, false]) {
        for (final labels in [true, false]) {
          paintOnce(make(
            gestures: {
              1: _gesture(id: 1, action: PointerAction.down, x: 0.1, y: 0.1),
              2: _gesture(id: 2, action: PointerAction.move, x: 1.0, y: 1.0),
              3: _gesture(id: 3, action: PointerAction.up),
            },
            scroll: _gesture(action: PointerAction.scroll, dx: -5, dy: 80),
            ripples: ripples,
            labels: labels,
          ));
        }
      }
    });

    testWidgets('paints safely on a zero-sized canvas', (tester) async {
      paintOnce(make(gestures: {1: _gesture()}), Size.zero);
    });
  });
}
