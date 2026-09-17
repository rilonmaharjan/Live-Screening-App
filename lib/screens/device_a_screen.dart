import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/mirror_protocol.dart';
import '../services/firebase_service.dart';
import '../services/frame_streamer.dart';
import '../services/gesture_tracker.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_showcase.dart';

class DeviceABroadcasterScreen extends StatefulWidget {
  final TransportMode transportMode;

  const DeviceABroadcasterScreen({
    super.key,
    this.transportMode = TransportMode.webSocket,
  });

  @override
  State<DeviceABroadcasterScreen> createState() => _DeviceABroadcasterScreenState();
}

class _DeviceABroadcasterScreenState extends State<DeviceABroadcasterScreen> {
  late IBroadcastService _broadcastService;
  WebSocketServerService? _wsService;
  FirebaseBroadcastService? _fbService;

  late FrameStreamerController _frameStreamer;
  late GestureTrackerController _gestureTracker;

  final TextEditingController _channelController = TextEditingController(text: 'live_stream');
  final List<String> _serverLogs = [];
  bool _showConnectionSheet = false;
  String _statusText = 'Initializing...';
  bool _isBroadcasting = false;
  int _clientCount = 0;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  void _initService() {
    if (widget.transportMode == TransportMode.webSocket) {
      _wsService = WebSocketServerService();
      _broadcastService = _wsService!;
    } else {
      _fbService = FirebaseBroadcastService();
      _broadcastService = _fbService!;
    }

    _frameStreamer = FrameStreamerController(broadcastService: _broadcastService);
    _gestureTracker = GestureTrackerController(broadcastService: _broadcastService);

    _setupBroadcast();
  }

  Future<void> _setupBroadcast() async {
    if (widget.transportMode == TransportMode.webSocket && _wsService != null) {
      _wsService!.onClientCountChanged = (count) {
        if (mounted) {
          setState(() {
            _clientCount = count;
            _statusText = 'Clients Connected: $count';
          });
        }
      };

      _wsService!.onLog = (log) {
        if (mounted) {
          setState(() {
            _serverLogs.insert(0, log);
            if (_serverLogs.length > 20) _serverLogs.removeLast();
          });
        }
      };

      final success = await _wsService!.startServer(port: 8080);
      if (mounted) {
        setState(() {
          _isBroadcasting = success;
          if (success) {
            _statusText = 'WebSocket Server: ws://${_wsService!.serverIp}:${_wsService!.port}';
            _frameStreamer.startStreaming(fps: 8);
          } else {
            _statusText = 'Failed to start WebSocket server';
          }
        });
      }
    } else if (widget.transportMode == TransportMode.firebase && _fbService != null) {
      _fbService!.onStatusChanged = (active, status) {
        if (mounted) {
          setState(() {
            _isBroadcasting = active;
            _statusText = status;
          });
          if (active && !_frameStreamer.isStreaming) {
            _frameStreamer.startStreaming(fps: 8);
          }
        }
      };

      _fbService!.onLog = (log) {
        if (mounted) {
          setState(() {
            _serverLogs.insert(0, log);
            if (_serverLogs.length > 20) _serverLogs.removeLast();
          });
        }
      };

      await _fbService!.startBroadcasting(channelId: _channelController.text.trim());
    }
  }

  @override
  void dispose() {
    _frameStreamer.stopStreaming();
    if (_wsService != null) {
      _wsService!.stopServer();
    }
    if (_fbService != null) {
      _fbService!.stopBroadcasting();
    }
    _channelController.dispose();
    super.dispose();
  }

  String get _qrData {
    if (widget.transportMode == TransportMode.webSocket && _wsService != null) {
      return '${_wsService!.serverIp}:${_wsService!.port}';
    } else if (_fbService != null) {
      return _fbService!.channelId;
    }
    return '127.0.0.1:8080';
  }

  String get _displayAddress {
    if (widget.transportMode == TransportMode.webSocket && _wsService != null) {
      return '${_wsService!.serverIp}:${_wsService!.port}';
    } else if (_fbService != null) {
      return _fbService!.channelId;
    }
    return 'live_stream';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isWebSocket = widget.transportMode == TransportMode.webSocket;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isWebSocket ? 'Device A: Broadcaster (WebSocket IP)' : 'Device A: Broadcaster (Firebase Cloud)',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            onPressed: () => setState(() => _showConnectionSheet = !_showConnectionSheet),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Root Screen Capture & Multi-touch Listener
          RepaintBoundary(
            key: _frameStreamer.repaintBoundaryKey,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) {
                _gestureTracker.handlePointerDown(e, screenSize);
                _frameStreamer.triggerImmediateFrame();
              },
              onPointerMove: (e) {
                _gestureTracker.handlePointerMove(e, screenSize);
                _frameStreamer.triggerImmediateFrame();
              },
              onPointerUp: (e) {
                _gestureTracker.handlePointerUp(e, screenSize);
                _frameStreamer.triggerImmediateFrame();
              },
              onPointerCancel: (e) {
                _gestureTracker.handlePointerCancel(e, screenSize);
                _frameStreamer.triggerImmediateFrame();
              },
              onPointerSignal: (e) {
                _gestureTracker.handlePointerSignal(e, screenSize);
                _frameStreamer.triggerImmediateFrame();
              },
              child: const InteractiveShowcaseApp(),
            ),
          ),

          // 2. Floating Status Bar Overlay
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: (isWebSocket ? AppColors.secondary : AppColors.primary).withValues(alpha: 0.4),
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isBroadcasting ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _isBroadcasting
                              ? (isWebSocket
                                  ? 'WEBSOCKET HOST ACTIVE: $_displayAddress'
                                  : 'FIREBASE STREAM ACTIVE: ${_fbService?.channelId}')
                              : _statusText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          isWebSocket
                              ? 'Connected Clients: $_clientCount | FPS: ${_frameStreamer.currentFps.toStringAsFixed(0)} / ${_frameStreamer.targetFps}'
                              : 'FPS: ${_frameStreamer.currentFps.toStringAsFixed(0)} / ${_frameStreamer.targetFps} | Gestures Logged: ${_gestureTracker.recentGesturesLog.length}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showConnectionDialog(context),
                    style: TextButton.styleFrom(
                      foregroundColor: isWebSocket ? AppColors.secondary : AppColors.primaryLight,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: Icon(isWebSocket ? Icons.qr_code_scanner_rounded : Icons.qr_code_rounded, size: 16),
                    label: Text(isWebSocket ? 'IP Address' : 'Channel ID', style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),

          // 3. Bottom Sliding Logs Drawer
          if (_showConnectionSheet)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 240,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  boxShadow: [BoxShadow(color: Colors.black87, blurRadius: 15)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isWebSocket ? 'WebSocket Server Logs & Controls' : 'Firebase Stream Logs & FPS',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Row(
                          children: [
                            const Text('FPS: ', style: TextStyle(fontSize: 12)),
                            DropdownButton<int>(
                              value: _frameStreamer.targetFps,
                              dropdownColor: AppColors.surface,
                              items: const [
                                DropdownMenuItem(value: 4, child: Text('4 FPS')),
                                DropdownMenuItem(value: 8, child: Text('8 FPS')),
                                DropdownMenuItem(value: 12, child: Text('12 FPS')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _frameStreamer.updateFps(val));
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _showConnectionSheet = false),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _serverLogs.length,
                        itemBuilder: (context, idx) {
                          return Text(
                            '> ${_serverLogs[idx]}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showConnectionDialog(BuildContext context) {
    final isWebSocket = widget.transportMode == TransportMode.webSocket;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                isWebSocket ? Icons.lan_rounded : Icons.cloud_sync_rounded,
                color: isWebSocket ? AppColors.secondary : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Text(isWebSocket ? 'WebSocket IP Host Code' : 'Firebase Channel Code'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isWebSocket
                    ? 'Enter this IP address on Device B app or open in any web browser to view live stream:'
                    : 'Enter this Channel ID on Device B (Mobile, Web, or Desktop) to join live mirror stream:',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (isWebSocket ? AppColors.secondary : AppColors.primary).withValues(alpha: 0.5),
                  ),
                ),
                child: SelectableText(
                  _displayAddress,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isWebSocket ? AppColors.secondary : AppColors.primaryLight,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: isWebSocket ? 'http://$_displayAddress' : _qrData,
                  version: QrVersions.auto,
                  size: 160.0,
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isWebSocket
                    ? 'Scan QR with phone camera or browser to view live stream'
                    : 'Firebase Cloud Firestore Stream Channel',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
