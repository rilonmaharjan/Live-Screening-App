import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/mirror_protocol.dart';

class ActiveTouchPoint {
  final int id;
  final Offset position;
  final Offset normalizedPosition;
  final DateTime timestamp;
  final PointerAction action;

  ActiveTouchPoint({
    required this.id,
    required this.position,
    required this.normalizedPosition,
    required this.timestamp,
    required this.action,
  });
}

class GestureTrackerController extends ChangeNotifier {
  final IBroadcastService broadcastService;
  final Map<int, ActiveTouchPoint> _activeTouches = {};
  final List<GesturePacket> _recentGesturesLog = [];
  int _lastMoveBroadcastMs = 0;

  Map<int, ActiveTouchPoint> get activeTouches => Map.unmodifiable(_activeTouches);
  List<GesturePacket> get recentGesturesLog => List.unmodifiable(_recentGesturesLog);

  GestureTrackerController({required this.broadcastService});

  void handlePointerDown(PointerDownEvent event, Size screenSize) {
    if (screenSize.width <= 0 || screenSize.height <= 0) return;

    final normX = (event.localPosition.dx / screenSize.width).clamp(0.0, 1.0);
    final normY = (event.localPosition.dy / screenSize.height).clamp(0.0, 1.0);

    final touch = ActiveTouchPoint(
      id: event.pointer,
      position: event.localPosition,
      normalizedPosition: Offset(normX, normY),
      timestamp: DateTime.now(),
      action: PointerAction.down,
    );

    _activeTouches[event.pointer] = touch;

    final packet = GesturePacket(
      action: PointerAction.down,
      pointerId: event.pointer,
      normalizedX: normX,
      normalizedY: normY,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      deviceWidth: screenSize.width,
      deviceHeight: screenSize.height,
    );

    _broadcastGesture(packet);
    notifyListeners();
  }

  void handlePointerMove(PointerMoveEvent event, Size screenSize) {
    if (screenSize.width <= 0 || screenSize.height <= 0) return;

    final normX = (event.localPosition.dx / screenSize.width).clamp(0.0, 1.0);
    final normY = (event.localPosition.dy / screenSize.height).clamp(0.0, 1.0);

    final touch = ActiveTouchPoint(
      id: event.pointer,
      position: event.localPosition,
      normalizedPosition: Offset(normX, normY),
      timestamp: DateTime.now(),
      action: PointerAction.move,
    );

    _activeTouches[event.pointer] = touch;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Throttle drag pointer move broadcasts to at most once per 50ms (~20 FPS)
    if (nowMs - _lastMoveBroadcastMs >= 50) {
      _lastMoveBroadcastMs = nowMs;

      final packet = GesturePacket(
        action: PointerAction.move,
        pointerId: event.pointer,
        normalizedX: normX,
        normalizedY: normY,
        timestamp: nowMs,
        deviceWidth: screenSize.width,
        deviceHeight: screenSize.height,
      );

      _broadcastGesture(packet);
    }
    notifyListeners();
  }

  void handlePointerUp(PointerUpEvent event, Size screenSize) {
    final normX = screenSize.width > 0
        ? (event.localPosition.dx / screenSize.width).clamp(0.0, 1.0)
        : 0.0;
    final normY = screenSize.height > 0
        ? (event.localPosition.dy / screenSize.height).clamp(0.0, 1.0)
        : 0.0;

    _activeTouches.remove(event.pointer);

    final packet = GesturePacket(
      action: PointerAction.up,
      pointerId: event.pointer,
      normalizedX: normX,
      normalizedY: normY,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      deviceWidth: screenSize.width,
      deviceHeight: screenSize.height,
    );

    _broadcastGesture(packet);
    notifyListeners();
  }

  void handlePointerCancel(PointerCancelEvent event, Size screenSize) {
    _activeTouches.remove(event.pointer);

    final packet = GesturePacket(
      action: PointerAction.cancel,
      pointerId: event.pointer,
      normalizedX: 0.0,
      normalizedY: 0.0,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      deviceWidth: screenSize.width,
      deviceHeight: screenSize.height,
    );

    _broadcastGesture(packet);
    notifyListeners();
  }

  void handlePointerSignal(PointerSignalEvent event, Size screenSize) {
    if (event is PointerScrollEvent && screenSize.width > 0 && screenSize.height > 0) {
      final normX = (event.localPosition.dx / screenSize.width).clamp(0.0, 1.0);
      final normY = (event.localPosition.dy / screenSize.height).clamp(0.0, 1.0);

      final packet = GesturePacket(
        action: PointerAction.scroll,
        pointerId: event.pointer,
        normalizedX: normX,
        normalizedY: normY,
        scrollDeltaX: event.scrollDelta.dx,
        scrollDeltaY: event.scrollDelta.dy,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        deviceWidth: screenSize.width,
        deviceHeight: screenSize.height,
      );

      _broadcastGesture(packet);
      notifyListeners();
    }
  }

  void _broadcastGesture(GesturePacket packet) {
    // Add to log (max 30 items)
    _recentGesturesLog.insert(0, packet);
    if (_recentGesturesLog.length > 30) {
      _recentGesturesLog.removeLast();
    }

    // Broadcast over Firebase Cloud Firestore to Device B
    if (broadcastService.isHosting) {
      broadcastService.broadcastGesture(packet);
    }
  }
}
