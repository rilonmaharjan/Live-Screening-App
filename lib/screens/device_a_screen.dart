import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/frame_streamer.dart';
import '../services/gesture_tracker.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import '../widgets/interactive_showcase.dart';

class DeviceABroadcasterScreen extends StatefulWidget {
  const DeviceABroadcasterScreen({super.key});

  @override
  State<DeviceABroadcasterScreen> createState() => _DeviceABroadcasterScreenState();
}

class _DeviceABroadcasterScreenState extends State<DeviceABroadcasterScreen> {
  final WebSocketServerService _serverService = WebSocketServerService();
  late FrameStreamerController _frameStreamer;
  late GestureTrackerController _gestureTracker;

  String _serverIp = '0.0.0.0';
  int _clientCount = 0;
  final List<String> _serverLogs = [];
  bool _showConnectionSheet = false;

  @override
  void initState() {
    super.initState();
    _frameStreamer = FrameStreamerController(serverService: _serverService);
    _gestureTracker = GestureTrackerController(serverService: _serverService);

    _setupServer();
  }

  Future<void> _setupServer() async {
    _serverService.onClientCountChanged = (count) {
      if (mounted) {
        setState(() {
          _clientCount = count;
        });
        if (count > 0 && !_frameStreamer.isStreaming) {
          _frameStreamer.startStreaming(fps: 24);
        } else if (count == 0) {
          _frameStreamer.stopStreaming();
        }
      }
    };

    _serverService.onLog = (log) {
      if (mounted) {
        setState(() {
          _serverLogs.insert(0, log);
          if (_serverLogs.length > 20) _serverLogs.removeLast();
        });
      }
    };

    await _serverService.startServer();
    if (mounted) {
      setState(() {
        _serverIp = _serverService.serverIp;
      });
    }
  }

  @override
  void dispose() {
    _frameStreamer.stopStreaming();
    _serverService.stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final serverUrl = 'ws://$_serverIp:${_serverService.port}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device A: Broadcaster'),
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

          // 2. Floating Server Telemetry & Status Bar Overlay
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                      color: _clientCount > 0 ? AppColors.success : AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _clientCount > 0
                              ? 'STREAMING LIVE to $_clientCount Receiver(s)'
                              : 'HOSTING at $_serverIp:${_serverService.port}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'FPS: ${_frameStreamer.currentFps.toStringAsFixed(0)} / ${_frameStreamer.targetFps} | Gestures Logged: ${_gestureTracker.recentGesturesLog.length}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showPairingDialog(context, serverUrl),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondary,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.qr_code, size: 16),
                    label: const Text('Pair IP', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),

          // 3. Optional Bottom Sliding Logs Drawer
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
                        const Text(
                          'Server Logs & Target FPS',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Row(
                          children: [
                            const Text('FPS: ', style: TextStyle(fontSize: 12)),
                            DropdownButton<int>(
                              value: _frameStreamer.targetFps,
                              dropdownColor: AppColors.surface,
                              items: const [
                                DropdownMenuItem(value: 15, child: Text('15 FPS')),
                                DropdownMenuItem(value: 24, child: Text('24 FPS')),
                                DropdownMenuItem(value: 30, child: Text('30 FPS')),
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

  void _showPairingDialog(BuildContext context, String serverUrl) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.wifi_tethering_rounded, color: AppColors.secondary),
              SizedBox(width: 10),
              Text('Device A Host Address'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter this IP address on Device B (Mobile or Windows) to start receiving live screen & gesture mirror:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: SelectableText(
                  _serverIp,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryLight,
                    letterSpacing: 1.2,
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
                  data: _serverIp,
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
                'WebSocket Server: $serverUrl',
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
