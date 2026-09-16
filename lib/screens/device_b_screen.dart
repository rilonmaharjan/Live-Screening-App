import 'dart:async';

import 'package:flutter/material.dart';

import '../models/mirror_protocol.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gesture_overlay_painter.dart';

class DeviceBReceiverScreen extends StatefulWidget {
  const DeviceBReceiverScreen({super.key});

  @override
  State<DeviceBReceiverScreen> createState() => _DeviceBReceiverScreenState();
}

class _DeviceBReceiverScreenState extends State<DeviceBReceiverScreen> {
  final WebSocketClientService _clientService = WebSocketClientService();
  final TextEditingController _ipController = TextEditingController();

  bool _isConnected = false;
  String _statusMessage = 'Disconnected';

  // Live Stream Data
  FramePacket? _currentFrame;
  final Map<int, GesturePacket> _activeGestures = {};
  GesturePacket? _latestScrollGesture;

  // Stream Metrics
  int _receivedFramesCount = 0;
  double _fps = 0.0;
  int _latencyMs = 0;
  DateTime _lastFpsCalcTime = DateTime.now();
  Timer? _fpsTimer;

  // Viewport Settings
  BoxFit _imageBoxFit = BoxFit.contain;
  final bool _showLabels = true;
  bool _showTelemetry = true;

  @override
  void initState() {
    super.initState();
    _initIpField();

    _clientService.onStatusChanged = (connected, status) {
      if (mounted) {
        setState(() {
          _isConnected = connected;
          _statusMessage = status;
        });
      }
    };

    _clientService.onFrameReceived = (frame) {
      if (mounted) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final latency = now - frame.timestamp;
        setState(() {
          _currentFrame = frame;
          _receivedFramesCount++;
          _latencyMs = latency.clamp(0, 5000);
        });
      }
    };

    _clientService.onGestureReceived = (gesture) {
      if (mounted) {
        setState(() {
          if (gesture.action == PointerAction.scroll) {
            _latestScrollGesture = gesture;
          } else if (gesture.action == PointerAction.up || gesture.action == PointerAction.cancel) {
            _activeGestures.remove(gesture.pointerId);
          } else {
            _activeGestures[gesture.pointerId] = gesture;
          }
        });
      }
    };

    // Calculate FPS timer
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      final elapsedSec = now.difference(_lastFpsCalcTime).inMilliseconds / 1000.0;
      if (elapsedSec > 0 && mounted) {
        setState(() {
          _fps = _receivedFramesCount / elapsedSec;
          _receivedFramesCount = 0;
          _lastFpsCalcTime = now;
        });
      }
    });
  }

  Future<void> _initIpField() async {
    final localIp = await IPHelper.getLocalIPAddress();
    if (localIp != '127.0.0.1') {
      final parts = localIp.split('.');
      if (parts.length == 4) {
        // Pre-fill IP subnet for convenience
        _ipController.text = '${parts[0]}.${parts[1]}.${parts[2]}.';
      }
    } else {
      _ipController.text = '192.168.1.';
    }
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _clientService.disconnect();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _toggleConnect() async {
    if (_isConnected) {
      await _clientService.disconnect();
    } else {
      final targetIp = _ipController.text.trim();
      if (targetIp.isEmpty) return;
      await _clientService.connect(targetIp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device B: Receiver Viewer'),
        actions: [
          IconButton(
            icon: Icon(
              _showTelemetry ? Icons.analytics_outlined : Icons.analytics_rounded,
              color: _showTelemetry ? AppColors.secondary : Colors.white,
            ),
            tooltip: 'Toggle Telemetry Overlay',
            onPressed: () => setState(() => _showTelemetry = !_showTelemetry),
          ),
          PopupMenuButton<BoxFit>(
            icon: const Icon(Icons.aspect_ratio_rounded),
            tooltip: 'Aspect Ratio Fitting',
            onSelected: (fit) => setState(() => _imageBoxFit = fit),
            itemBuilder: (context) => const [
              PopupMenuItem(value: BoxFit.contain, child: Text('Fit Screen (Contain)')),
              PopupMenuItem(value: BoxFit.fill, child: Text('Fill Stretch (Fill)')),
              PopupMenuItem(value: BoxFit.cover, child: Text('Zoom Cover (Cover)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. IP Connection Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ipController,
                    enabled: !_isConnected,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Device A IP Address (e.g. 192.168.1.50)',
                      isDense: true,
                      prefixIcon: Icon(Icons.wifi_rounded, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _toggleConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? AppColors.accent : AppColors.primary,
                  ),
                  icon: Icon(_isConnected ? Icons.link_off_rounded : Icons.link_rounded),
                  label: Text(_isConnected ? 'Disconnect' : 'Connect'),
                ),
              ],
            ),
          ),

          // 2. Main Live Viewer & Gesture Overlay Canvas
          Expanded(
            child: Stack(
              children: [
                // Background void
                Container(color: Colors.black),

                // Mirrored Frame Display
                if (_currentFrame != null)
                  Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Image.memory(
                              _currentFrame!.imageBytes,
                              width: constraints.maxWidth,
                              height: constraints.maxHeight,
                              fit: _imageBoxFit,
                              gaplessPlayback: true,
                            ),

                            // Live Gesture & Tap Overlay
                            Positioned.fill(
                              child: LiveGestureOverlay(
                                activeGestures: _activeGestures,
                                latestScroll: _latestScrollGesture,
                                canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
                                showLabels: _showLabels,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isConnected ? Icons.screen_search_desktop_rounded : Icons.phonelink_erase_rounded,
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isConnected
                              ? 'Connected to Device A!\nWaiting for live screen frames...'
                              : 'Enter Device A IPv4 address above and tap Connect.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ],
                    ),
                  ),

                // 3. Telemetry Overlay Dashboard
                if (_showTelemetry && _isConnected)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Row(
                            children: [
                              CircleAvatar(radius: 4, backgroundColor: AppColors.success),
                              SizedBox(width: 6),
                              Text(
                                'MIRROR STREAM LIVE',
                                style: TextStyle(
                                  color: AppColors.success,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'FPS: ${_fps.toStringAsFixed(1)} | Latency: ${_latencyMs}ms',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          if (_currentFrame != null)
                            Text(
                              'Resolution: ${_currentFrame!.width}x${_currentFrame!.height} (${(_currentFrame!.imageBytes.length / 1024).toStringAsFixed(1)} KB)',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                            ),
                          Text(
                            'Active Touches: ${_activeGestures.length}',
                            style: const TextStyle(color: AppColors.secondary, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 3. Status Bar Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surface,
            child: Row(
              children: [
                Icon(
                  _isConnected ? Icons.check_circle_rounded : Icons.info_rounded,
                  size: 16,
                  color: _isConnected ? AppColors.success : AppColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: _isConnected ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
