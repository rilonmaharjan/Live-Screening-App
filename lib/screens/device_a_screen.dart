import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rndscreeningap/widgets/museum_poi.dart';

import '../models/mirror_protocol.dart';
import '../models/museum_item.dart';
import '../services/firebase_service.dart';
import '../services/frame_streamer.dart';
import '../services/gesture_tracker.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import '../widgets/museum_map_view.dart';

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
  final bool _showConnectionSheet = false;
  String _statusText = 'Initializing...';
  bool _isBroadcasting = false;
  int _clientCount = 0;
  int _selectedTabIndex = 0;
  bool _switchValue = true;
  double _sliderValue = 65.0;
  final List<Offset?> _drawnPoints = [];

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

  String get _status {
    if (widget.transportMode == TransportMode.webSocket && _wsService != null) {
      return _wsService!.serverIp;
    }
    if (_fbService != null) {
      return _fbService!.channelId;
    }
    return _statusText;
  }

  WebSocketServerService? get _server => _wsService;

  @override
  Widget build(BuildContext context) {
    final isWebSocket = widget.transportMode == TransportMode.webSocket;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(
          isWebSocket ? 'Device A: Broadcaster' : 'Device A: Broadcaster',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildInteractiveDashboard(),
                MuseumMapView(pois: MuseumPoi.samplePois),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: Color(0xFF334155)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: _buildNavItem(
                      index: 0,
                      icon: Icons.dashboard_rounded,
                      label: 'Dashboard',
                    ),
                  ),
                  Expanded(
                    child: _buildNavItem(
                      index: 1,
                      icon: Icons.map_rounded,
                      label: 'Museum Map',
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

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? AppColors.primaryLight : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveDashboard() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildServerStatusCard(),
          const SizedBox(height: 16),
          _buildControlsCard(),
          const SizedBox(height: 16),
          _buildPoiGrid(),
          const SizedBox(height: 16),
          _buildDrawingArea(),
        ],
      ),
    );
  }

  Widget _buildServerStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering_rounded, size: 32, color: Colors.tealAccent),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LOCAL WI-FI ADDRESS (WEBSOCKET)',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _status,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: Colors.tealAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _server?.serverIp ?? _status));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('IP Address copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white60),
                        tooltip: 'Copy IP',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.devices_rounded, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Text(
                  'Connected WebSocket Clients: $_clientCount',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: Colors.tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'Interactive UI Controls',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Host Feature Toggle:', style: TextStyle(color: Colors.white70, fontSize: 14)),
              Switch(
                value: _switchValue,
                activeThumbColor: Colors.tealAccent,
                onChanged: (val) => setState(() => _switchValue = val),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sync Level: ${_sliderValue.toInt()}%',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Slider(
                value: _sliderValue,
                min: 0,
                max: 100,
                activeColor: Colors.tealAccent,
                inactiveColor: const Color(0xFF334155),
                onChanged: (val) => setState(() => _sliderValue = val),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPoiGrid() {
    final pois = MuseumItem.sampleItems;
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.museum_rounded, color: Colors.tealAccent, size: 20),
              SizedBox(width: 8),
              Text(
                'Museum Highlights',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 24),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: pois.length,
            itemBuilder: (context, index) {
              final poi = pois[index];
              return InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Selected ${poi.name}'),
                      backgroundColor: Colors.teal,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Row(
                    children: [
                      Icon(poi.icon, color: Colors.tealAccent, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          poi.name,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawingArea() {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.gesture_rounded, color: Colors.tealAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Live Drawing Pad',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => setState(() => _drawnPoints.clear()),
                icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                label: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
              )
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 16),
          const SizedBox(height: 8),
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              border: Border.all(color: const Color(0xFF334155)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() => _drawnPoints.add(details.localPosition));
                },
                onPanUpdate: (details) {
                  setState(() => _drawnPoints.add(details.localPosition));
                },
                onPanEnd: (_) {
                  setState(() => _drawnPoints.add(null));
                },
                child: CustomPaint(
                  painter: _DrawingPainter(_drawnPoints),
                  size: Size.infinite,
                ),
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

class _DrawingPainter extends CustomPainter {
  final List<Offset?> points;

  _DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.tealAccent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0;

    for (int i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      if (current != null && next != null) {
        canvas.drawLine(current, next, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => oldDelegate.points != points;
}
