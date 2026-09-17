import 'dart:async';

import 'package:flutter/material.dart';

import '../models/mirror_protocol.dart';
import '../services/firebase_service.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gesture_overlay_painter.dart';

class DeviceBReceiverScreen extends StatefulWidget {
  final TransportMode transportMode;

  const DeviceBReceiverScreen({
    super.key,
    this.transportMode = TransportMode.webSocket,
  });

  @override
  State<DeviceBReceiverScreen> createState() => _DeviceBReceiverScreenState();
}

class _DeviceBReceiverScreenState extends State<DeviceBReceiverScreen> {
  WebSocketClientService? _wsClient;
  FirebaseBroadcastService? _fbService;

  late TextEditingController _addressController;

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

    final defaultText = widget.transportMode == TransportMode.webSocket
        ? '192.168.1.'
        : 'live_stream';
    _addressController = TextEditingController(text: defaultText);
    _addressController.selection = TextSelection.fromPosition(
      TextPosition(offset: defaultText.length),
    );

    _initReceiver();

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

    if (widget.transportMode == TransportMode.firebase) {
      _connect();
    } else {
      _statusMessage = 'Enter Host IP (e.g. 192.168.1.50:8080) and tap Connect';
    }
  }

  void _initReceiver() {
    if (widget.transportMode == TransportMode.webSocket) {
      _wsClient = WebSocketClientService();

      _wsClient!.onStatusChanged = (connected, status) {
        if (mounted) {
          setState(() {
            _isConnected = connected;
            _statusMessage = status;
          });
        }
      };

      _wsClient!.onFrameReceived = (frame) {
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

      _wsClient!.onGestureReceived = (gesture) {
        _handleIncomingGesture(gesture);
      };
    } else {
      _fbService = FirebaseBroadcastService();

      _fbService!.onStatusChanged = (connected, status) {
        if (mounted) {
          setState(() {
            _isConnected = connected;
            _statusMessage = status;
          });
        }
      };

      _fbService!.onFrameReceived = (frame) {
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

      _fbService!.onGestureReceived = (gesture) {
        _handleIncomingGesture(gesture);
      };
    }
  }

  void _handleIncomingGesture(GesturePacket gesture) {
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
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    if (_wsClient != null) {
      _wsClient!.disconnect();
    }
    if (_fbService != null) {
      _fbService!.disconnect();
    }
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final target = _addressController.text.trim();
    if (target.isEmpty) return;

    if (widget.transportMode == TransportMode.webSocket && _wsClient != null) {
      await _wsClient!.connect(target);
    } else if (_fbService != null) {
      await _fbService!.connectToBroadcast(channelId: target);
    }
  }

  Future<void> _toggleConnect() async {
    if (_isConnected) {
      if (_wsClient != null) await _wsClient!.disconnect();
      if (_fbService != null) await _fbService!.disconnect();
    } else {
      await _connect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWebSocket = widget.transportMode == TransportMode.webSocket;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isWebSocket ? 'Device B: Receiver (WebSocket IP)' : 'Device B: Receiver (Firebase Cloud)',
        ),
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
          // 1. Connection Target Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addressController,
                    enabled: !_isConnected,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: isWebSocket
                          ? 'Host IP Address (e.g. 192.168.1.50:8080)'
                          : 'Firebase Channel ID (e.g. live_stream)',
                      isDense: true,
                      prefixIcon: Icon(
                        isWebSocket ? Icons.lan_rounded : Icons.cloud_queue_rounded,
                        size: 20,
                        color: isWebSocket ? AppColors.secondary : AppColors.primaryLight,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _toggleConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected
                        ? AppColors.accent
                        : (isWebSocket ? AppColors.secondary : AppColors.primary),
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
                          _isConnected
                              ? (isWebSocket ? Icons.wifi_tethering_rounded : Icons.cloud_sync_rounded)
                              : (isWebSocket ? Icons.wifi_off_rounded : Icons.cloud_off_rounded),
                          size: 64,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isConnected
                              ? (isWebSocket
                                  ? 'Connected to WebSocket Host!\nWaiting for live screen frames...'
                                  : 'Connected to Firebase Channel!\nWaiting for live screen frames...')
                              : (isWebSocket
                                  ? 'Enter Host IP Address (e.g. 192.168.1.50:8080) and tap Connect.'
                                  : 'Enter Firebase Channel ID above and tap Connect.'),
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
                        border: Border.all(
                          color: (isWebSocket ? AppColors.secondary : AppColors.primary).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(radius: 4, backgroundColor: AppColors.success),
                              const SizedBox(width: 6),
                              Text(
                                isWebSocket ? 'WEBSOCKET STREAM LIVE' : 'FIREBASE STREAM LIVE',
                                style: const TextStyle(
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
