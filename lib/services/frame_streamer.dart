import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/mirror_protocol.dart';
import 'network_service.dart';

class FrameStreamerController {
  final GlobalKey repaintBoundaryKey = GlobalKey();
  final WebSocketServerService serverService;

  Timer? _captureTimer;
  bool _isStreaming = false;
  bool _isProcessingFrame = false;
  int _targetFps = 30;
  double _currentFps = 0.0;
  int _framesCaptured = 0;
  DateTime _lastFpsCalculationTime = DateTime.now();

  bool get isStreaming => _isStreaming;
  double get currentFps => _currentFps;
  int get targetFps => _targetFps;

  FrameStreamerController({required this.serverService});

  void startStreaming({int fps = 30}) {
    if (_isStreaming) return;
    _targetFps = fps;
    _isStreaming = true;
    _isProcessingFrame = false;
    _framesCaptured = 0;
    _lastFpsCalculationTime = DateTime.now();

    final intervalMs = (1000 / _targetFps).round();
    _captureTimer = Timer.periodic(
      Duration(milliseconds: intervalMs),
      (_) => _captureAndBroadcastFrame(),
    );
  }

  void updateFps(int newFps) {
    if (_targetFps == newFps) return;
    _targetFps = newFps;
    if (_isStreaming) {
      stopStreaming();
      startStreaming(fps: _targetFps);
    }
  }

  /// Trigger an immediate HD frame capture on live user touch, drag, or scroll
  void triggerImmediateFrame() {
    if (!_isStreaming || serverService.clientCount == 0 || _isProcessingFrame) return;
    scheduleMicrotask(() => _captureAndBroadcastFrame());
  }

  Future<void> _captureAndBroadcastFrame() async {
    if (!_isStreaming || serverService.clientCount == 0 || _isProcessingFrame) return;

    _isProcessingFrame = true;
    try {
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null || !boundary.attached || boundary.debugNeedsPaint) {
        return;
      }

      final size = boundary.size;
      if (size.width <= 0 || size.height <= 0) return;

      // High-Definition Crisp Quality: Target ~720px width resolution for sharp UI display on Device B
      const double targetWidth = 720.0;
      final double pixelRatio = (targetWidth / size.width).clamp(0.4, 0.75);

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData != null) {
        final imageBytes = byteData.buffer.asUint8List();
        final framePacket = FramePacket(
          imageBytes: imageBytes,
          aspectRatio: size.width / size.height,
          width: size.width.toInt(),
          height: size.height.toInt(),
          timestamp: DateTime.now().millisecondsSinceEpoch,
          currentFps: _currentFps,
        );

        // Broadcast frame packet over WebSocket
        serverService.broadcast(framePacket.toBase64Json());

        // FPS counter calculation
        _framesCaptured++;
        final now = DateTime.now();
        final elapsedSec = now.difference(_lastFpsCalculationTime).inMilliseconds / 1000.0;
        if (elapsedSec >= 1.0) {
          _currentFps = _framesCaptured / elapsedSec;
          _framesCaptured = 0;
          _lastFpsCalculationTime = now;
        }
      }
    } catch (e) {
      // Catch frame capture errors gracefully
    } finally {
      _isProcessingFrame = false;
    }
  }

  void stopStreaming() {
    _isStreaming = false;
    _captureTimer?.cancel();
    _captureTimer = null;
    _isProcessingFrame = false;
    _currentFps = 0.0;
  }
}
