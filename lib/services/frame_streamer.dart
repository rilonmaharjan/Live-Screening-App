import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/mirror_protocol.dart';

class FrameStreamerController {
  final GlobalKey repaintBoundaryKey = GlobalKey();
  final IBroadcastService broadcastService;

  Timer? _captureTimer;
  bool _isStreaming = false;
  bool _isProcessingFrame = false;
  int _targetFps = 8; // High-performance real-time stream rate
  double _currentFps = 0.0;
  int _framesCaptured = 0;
  DateTime _lastFpsCalculationTime = DateTime.now();
  int _lastUploadMs = 0;

  bool get isStreaming => _isStreaming;
  double get currentFps => _currentFps;
  int get targetFps => _targetFps;

  FrameStreamerController({required this.broadcastService});

  void startStreaming({int fps = 8}) {
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

  /// Trigger an immediate ultra-fast frame capture on live user touch, drag, or scroll
  void triggerImmediateFrame() {
    if (!_isStreaming || !broadcastService.isHosting || _isProcessingFrame) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    // Allow rapid capture with 60ms gap (~16 FPS max bursts)
    if (nowMs - _lastUploadMs < 60) return;
    scheduleMicrotask(() => _captureAndBroadcastFrame());
  }

  Future<void> _captureAndBroadcastFrame() async {
    if (!_isStreaming || !broadcastService.isHosting || _isProcessingFrame) return;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastUploadMs < 60) return;

    _isProcessingFrame = true;
    try {
      final boundary = repaintBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null || !boundary.attached || boundary.debugNeedsPaint) {
        return;
      }

      final size = boundary.size;
      if (size.width <= 0 || size.height <= 0) return;

      // Compact resolution (~280px width) for ~10-18 KB payloads & ~8ms PNG render time
      const double targetWidth = 280.0;
      final double pixelRatio = (targetWidth / size.width).clamp(0.15, 0.4);

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
          timestamp: nowMs,
          currentFps: _currentFps,
        );

        _lastUploadMs = nowMs;

        // Non-blocking broadcast over Firebase Cloud Firestore
        unawaited(broadcastService.broadcastFrame(framePacket));

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
