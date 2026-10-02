import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/models/mirror_protocol.dart';
import 'package:rndscreeningap/services/gesture_tracker.dart';

import '../helpers/fakes.dart';

void main() {
  const screen = Size(400, 800);
  late FakeBroadcastService service;
  late GestureTrackerController tracker;

  setUp(() {
    service = FakeBroadcastService();
    tracker = GestureTrackerController(broadcastService: service);
  });

  group('pointer down', () {
    test('normalizes the position and broadcasts a down packet', () {
      tracker.handlePointerDown(
        const PointerDownEvent(pointer: 1, position: Offset(100, 400)),
        screen,
      );

      expect(service.gestures, hasLength(1));
      final packet = service.gestures.single;
      expect(packet.action, PointerAction.down);
      expect(packet.pointerId, 1);
      expect(packet.normalizedX, closeTo(0.25, 1e-9));
      expect(packet.normalizedY, closeTo(0.5, 1e-9));
      expect(packet.deviceWidth, 400);
      expect(packet.deviceHeight, 800);
    });

    test('registers an active touch', () {
      tracker.handlePointerDown(
        const PointerDownEvent(pointer: 5, position: Offset(40, 80)),
        screen,
      );

      expect(tracker.activeTouches.keys, [5]);
      final touch = tracker.activeTouches[5]!;
      expect(touch.position, const Offset(40, 80));
      expect(touch.normalizedPosition.dx, closeTo(0.1, 1e-9));
      expect(touch.normalizedPosition.dy, closeTo(0.1, 1e-9));
      expect(touch.action, PointerAction.down);
    });

    test('clamps out-of-bounds positions to 0..1', () {
      tracker.handlePointerDown(
        const PointerDownEvent(pointer: 1, position: Offset(-50, 5000)),
        screen,
      );
      final packet = service.gestures.single;
      expect(packet.normalizedX, 0.0);
      expect(packet.normalizedY, 1.0);
    });

    test('ignores events when the screen size is zero', () {
      tracker.handlePointerDown(
        const PointerDownEvent(pointer: 1, position: Offset(10, 10)),
        Size.zero,
      );
      expect(service.gestures, isEmpty);
      expect(tracker.activeTouches, isEmpty);
    });

    test('supports multiple simultaneous pointers', () {
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 1, position: Offset(10, 10)), screen);
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 2, position: Offset(20, 20)), screen);
      expect(tracker.activeTouches.keys, unorderedEquals([1, 2]));
    });
  });

  group('pointer move', () {
    test('updates the active touch position', () {
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 1, position: Offset(0, 0)), screen);
      tracker.handlePointerMove(
          const PointerMoveEvent(pointer: 1, position: Offset(200, 400)), screen);

      final touch = tracker.activeTouches[1]!;
      expect(touch.action, PointerAction.move);
      expect(touch.normalizedPosition.dx, closeTo(0.5, 1e-9));
      expect(touch.normalizedPosition.dy, closeTo(0.5, 1e-9));
    });

    test('throttles broadcasts but always updates local state', () {
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 1, position: Offset(0, 0)), screen);
      service.gestures.clear();

      // A tight loop finishes in far less than the 50 ms throttle window.
      for (var i = 0; i < 25; i++) {
        tracker.handlePointerMove(
          PointerMoveEvent(pointer: 1, position: Offset(i.toDouble(), 0)),
          screen,
        );
      }

      expect(service.gestures, isNotEmpty);
      expect(service.gestures.length, lessThan(25));
      expect(service.gestures.every((g) => g.action == PointerAction.move), isTrue);
      // Local state still tracked the final position.
      expect(tracker.activeTouches[1]!.position, const Offset(24, 0));
    });

    test('ignores events when the screen size is zero', () {
      tracker.handlePointerMove(
        const PointerMoveEvent(pointer: 1, position: Offset(10, 10)),
        Size.zero,
      );
      expect(service.gestures, isEmpty);
      expect(tracker.activeTouches, isEmpty);
    });
  });

  group('pointer up / cancel', () {
    test('up removes the touch and broadcasts an up packet', () {
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 1, position: Offset(100, 200)), screen);
      tracker.handlePointerUp(
          const PointerUpEvent(pointer: 1, position: Offset(100, 200)), screen);

      expect(tracker.activeTouches, isEmpty);
      expect(service.gestures.last.action, PointerAction.up);
      expect(service.gestures.last.normalizedX, closeTo(0.25, 1e-9));
    });

    test('up with a zero screen size reports 0,0 instead of dividing by zero', () {
      tracker.handlePointerUp(
          const PointerUpEvent(pointer: 1, position: Offset(100, 200)), Size.zero);
      final packet = service.gestures.single;
      expect(packet.normalizedX, 0.0);
      expect(packet.normalizedY, 0.0);
    });

    test('cancel removes the touch and broadcasts a cancel packet', () {
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 9, position: Offset(1, 1)), screen);
      tracker.handlePointerCancel(const PointerCancelEvent(pointer: 9), screen);

      expect(tracker.activeTouches, isEmpty);
      expect(service.gestures.last.action, PointerAction.cancel);
      expect(service.gestures.last.pointerId, 9);
    });
  });

  group('pointer signal (scroll)', () {
    test('broadcasts scroll deltas with normalized position', () {
      tracker.handlePointerSignal(
        const PointerScrollEvent(
          position: Offset(200, 400),
          scrollDelta: Offset(3, 40),
        ),
        screen,
      );

      final packet = service.gestures.single;
      expect(packet.action, PointerAction.scroll);
      expect(packet.scrollDeltaX, 3);
      expect(packet.scrollDeltaY, 40);
      expect(packet.normalizedX, closeTo(0.5, 1e-9));
      expect(packet.normalizedY, closeTo(0.5, 1e-9));
    });

    test('ignores non-scroll signals', () {
      tracker.handlePointerSignal(
        const PointerScaleEvent(position: Offset(1, 1), scale: 2),
        screen,
      );
      expect(service.gestures, isEmpty);
    });
  });

  group('broadcasting & log', () {
    test('does not broadcast while the service is not hosting', () {
      service.hosting = false;
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 1, position: Offset(10, 10)), screen);

      expect(service.gestures, isEmpty);
      // ...but the gesture is still logged locally.
      expect(tracker.recentGesturesLog, hasLength(1));
    });

    test('keeps the newest gesture first and caps the log at 30', () {
      for (var i = 0; i < 40; i++) {
        tracker.handlePointerDown(
          PointerDownEvent(pointer: i, position: const Offset(10, 10)),
          screen,
        );
      }

      final log = tracker.recentGesturesLog;
      expect(log, hasLength(30));
      expect(log.first.pointerId, 39);
      expect(log.last.pointerId, 10);
    });

    test('exposed collections are unmodifiable', () {
      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 1, position: Offset(10, 10)), screen);
      expect(() => tracker.activeTouches.clear(), throwsUnsupportedError);
      expect(() => tracker.recentGesturesLog.clear(), throwsUnsupportedError);
    });

    test('notifies listeners on every handled event', () {
      var notifications = 0;
      tracker.addListener(() => notifications++);

      tracker.handlePointerDown(
          const PointerDownEvent(pointer: 1, position: Offset(10, 10)), screen);
      tracker.handlePointerUp(
          const PointerUpEvent(pointer: 1, position: Offset(10, 10)), screen);
      tracker.handlePointerCancel(const PointerCancelEvent(pointer: 2), screen);

      expect(notifications, 3);
    });
  });
}
