import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/mirror_protocol.dart';

class IPHelper {
  /// Get the active primary IPv4 address of the local network interface
  static Future<String> getLocalIPAddress() async {
    if (kIsWeb) return '127.0.0.1';
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        // Prioritize Wi-Fi and Ethernet interfaces
        final isWifiOrEth = interface.name.toLowerCase().contains('wlan') ||
            interface.name.toLowerCase().contains('wifi') ||
            interface.name.toLowerCase().contains('eth') ||
            interface.name.toLowerCase().contains('en');

        if (isWifiOrEth) {
          for (final addr in interface.addresses) {
            if (!addr.isLoopback) {
              return addr.address;
            }
          }
        }
      }

      // Fallback: first non-loopback address
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // Ignore network search failure
    }
    return '127.0.0.1';
  }
}

class WebSocketServerService {
  HttpServer? _server;
  final List<WebSocket> _connectedClients = [];
  int _port = 8080;
  String _serverIp = '0.0.0.0';
  bool _isHosting = false;

  // Callbacks
  Function(int clientCount)? onClientCountChanged;
  Function(GesturePacket gesture)? onGestureReceived;
  Function(String log)? onLog;

  bool get isHosting => _isHosting;
  String get serverIp => _serverIp;
  int get port => _port;
  int get clientCount => _connectedClients.length;

  Future<bool> startServer({int port = 8080}) async {
    if (kIsWeb) {
      _log('Hosting server is not supported directly in web browser target. Use Mobile or Desktop for Device A.');
      return false;
    }
    _port = port;
    try {
      _serverIp = await IPHelper.getLocalIPAddress();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _port);
      _isHosting = true;
      _log('Server started on ws://$_serverIp:$_port (Web Viewer available at http://$_serverIp:$_port)');

      _server!.listen((HttpRequest request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final clientIp = request.connectionInfo?.remoteAddress.address ?? 'Client';
          final socket = await WebSocketTransformer.upgrade(request);
          _handleClientConnection(socket, clientIp);
        } else {
          // Serve built-in HTML5 Web Viewer so Device B can be ANY web browser!
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.html
            ..write(_getWebViewerHtml())
            ..close();
        }
      });

      return true;
    } catch (e) {
      _log('Failed to start server: $e');
      _isHosting = false;
      return false;
    }
  }

  void _handleClientConnection(WebSocket socket, String clientIp) {
    _connectedClients.add(socket);
    _log('Client connected from $clientIp. Total clients: ${_connectedClients.length}');
    onClientCountChanged?.call(_connectedClients.length);

    socket.listen(
      (data) {
        if (data is String) {
          _handleIncomingMessage(data);
        }
      },
      onDone: () {
        _connectedClients.remove(socket);
        _log('Client disconnected. Remaining: ${_connectedClients.length}');
        onClientCountChanged?.call(_connectedClients.length);
      },
      onError: (err) {
        _connectedClients.remove(socket);
        _log('Client connection error: $err');
        onClientCountChanged?.call(_connectedClients.length);
      },
    );
  }

  void _handleIncomingMessage(String messageStr) {
    try {
      final json = jsonDecode(messageStr) as Map<String, dynamic>;
      final type = json['type'] as String?;
      if (type == 'gesture') {
        final gesture = GesturePacket.fromJson(json);
        onGestureReceived?.call(gesture);
      }
    } catch (e) {
      // Ignore malformed packet
    }
  }

  /// Broadcast frame or gesture data string to all connected Device B clients
  void broadcast(String payload) {
    if (_connectedClients.isEmpty) return;
    final deadSockets = <WebSocket>[];
    for (final socket in _connectedClients) {
      try {
        socket.add(payload);
      } catch (e) {
        deadSockets.add(socket);
      }
    }
    for (final dead in deadSockets) {
      _connectedClients.remove(dead);
      onClientCountChanged?.call(_connectedClients.length);
    }
  }

  Future<void> stopServer() async {
    for (final socket in _connectedClients) {
      await socket.close();
    }
    _connectedClients.clear();
    await _server?.close(force: true);
    _server = null;
    _isHosting = false;
    _log('Server stopped');
  }

  void _log(String msg) {
    onLog?.call(msg);
  }

  /// Self-contained HTML5 + JavaScript Web Viewer served directly to Device B web browsers
  String _getWebViewerHtml() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Device A Live Screen & Gesture Mirror</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background-color: #0F172A;
      color: #F8FAFC;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      display: flex;
      flex-direction: column;
      height: 100vh;
      overflow: hidden;
    }
    header {
      background: #1E293B;
      padding: 12px 20px;
      display: flex;
      align-items: center;
      justify-content: space-between;
      border-bottom: 1px solid rgba(255,255,255,0.1);
    }
    .badge {
      background: rgba(16, 185, 129, 0.2);
      color: #10B981;
      padding: 4px 10px;
      border-radius: 20px;
      font-weight: bold;
      font-size: 12px;
      border: 1px solid rgba(16, 185, 129, 0.4);
    }
    .container {
      flex: 1;
      position: relative;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #000;
    }
    #screen-img {
      max-width: 100%;
      max-height: 100%;
      object-fit: contain;
    }
    #gesture-canvas {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      pointer-events: none;
    }
    .stats {
      position: absolute;
      top: 16px;
      left: 16px;
      background: rgba(0, 0, 0, 0.85);
      padding: 10px 14px;
      border-radius: 10px;
      font-size: 12px;
      border: 1px solid rgba(6, 182, 212, 0.4);
      color: #06B6D4;
    }
  </style>
</head>
<body>
  <header>
    <div>
      <h3 style="font-size: 16px; color: #818CF8;">Device B Web Viewer</h3>
      <span style="font-size: 11px; color: #94A3B8;">Mirrored from Device A Host</span>
    </div>
    <div id="status-badge" class="badge">CONNECTING...</div>
  </header>
  <div class="container" id="viewer-container">
    <img id="screen-img" alt="Device A Screen Stream" />
    <canvas id="gesture-canvas"></canvas>
    <div class="stats" id="stats-panel">FPS: 0 | Latency: 0ms</div>
  </div>

  <script>
    const wsUrl = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host;
    const imgEl = document.getElementById('screen-img');
    const canvas = document.getElementById('gesture-canvas');
    const ctx = canvas.getContext('2d');
    const badge = document.getElementById('status-badge');
    const statsEl = document.getElementById('stats-panel');

    let ws = new WebSocket(wsUrl);
    let activePointers = new Map();
    let lastFrameTime = performance.now();
    let frameCount = 0;
    let fps = 0;

    function resizeCanvas() {
      canvas.width = canvas.clientWidth;
      canvas.height = canvas.clientHeight;
    }
    window.addEventListener('resize', resizeCanvas);

    ws.onopen = () => {
      badge.textContent = 'LIVE MIRROR ACTIVE';
      badge.style.background = 'rgba(16, 185, 129, 0.2)';
      badge.style.color = '#10B981';
      resizeCanvas();
    };

    ws.onclose = () => {
      badge.textContent = 'DISCONNECTED';
      badge.style.background = 'rgba(244, 63, 94, 0.2)';
      badge.style.color = '#F43F5E';
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (data.type === 'frame') {
          imgEl.src = 'data:image/png;base64,' + data.base64;
          frameCount++;
          const now = performance.now();
          if (now - lastFrameTime >= 1000) {
            fps = frameCount;
            frameCount = 0;
            lastFrameTime = now;
            const latency = Date.now() - (data.timestamp || Date.now());
            statsEl.textContent = `FPS: \${fps} | Latency: \${Math.max(0, latency)}ms | Res: \${data.width}x\${data.height}`;
          }
        } else if (data.type === 'gesture') {
          if (data.action === 'up' || data.action === 'cancel') {
            activePointers.delete(data.pointerId);
          } else {
            activePointers.set(data.pointerId, data);
          }
          drawOverlay();
        }
      } catch (e) {}
    };

    function drawOverlay() {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const imgRect = imgEl.getBoundingClientRect();
      const containerRect = document.getElementById('viewer-container').getBoundingClientRect();

      activePointers.forEach((p) => {
        const x = imgRect.left - containerRect.left + p.normalizedX * imgRect.width;
        const y = imgRect.top - containerRect.top + p.normalizedY * imgRect.height;

        // Draw Touch Ripple Dot
        ctx.beginPath();
        ctx.arc(x, y, 18, 0, 2 * Math.PI);
        ctx.fillStyle = 'rgba(244, 63, 94, 0.4)';
        ctx.fill();

        ctx.beginPath();
        ctx.arc(x, y, 10, 0, 2 * Math.PI);
        ctx.fillStyle = '#F43F5E';
        ctx.fill();

        ctx.beginPath();
        ctx.arc(x, y, 4, 0, 2 * Math.PI);
        ctx.fillStyle = '#FFF';
        ctx.fill();
      });
    }

    setInterval(drawOverlay, 30);
  </script>
</body>
</html>
''';
  }
}

class WebSocketClientService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  String _targetIp = '';
  int _port = 8080;

  // Callbacks
  Function(FramePacket frame)? onFrameReceived;
  Function(GesturePacket gesture)? onGestureReceived;
  Function(SystemHandshakePacket handshake)? onHandshakeReceived;
  Function(bool connected, String status)? onStatusChanged;

  bool get isConnected => _isConnected;
  String get targetIp => _targetIp;

  Future<bool> connect(String ipAddress, {int port = 8080}) async {
    String cleaned = ipAddress.trim();
    // Remove protocol schemes if user pasted URL
    cleaned = cleaned.replaceAll(RegExp(r'^https?://|^wss?://'), '');

    int targetPort = port;
    if (cleaned.contains(':')) {
      final parts = cleaned.split(':');
      cleaned = parts[0];
      if (parts.length > 1) {
        targetPort = int.tryParse(parts[1]) ?? port;
      }
    }

    _targetIp = cleaned;
    _port = targetPort;
    onStatusChanged?.call(false, 'Connecting to ws://$_targetIp:$_port...');

    try {
      final wsUri = Uri.parse('ws://$_targetIp:$_port');
      _channel = WebSocketChannel.connect(wsUri);
      
      _subscription = _channel!.stream.listen(
        (data) {
          if (!_isConnected) {
            _isConnected = true;
            onStatusChanged?.call(true, 'Connected to Device A!');
          }
          if (data is String) {
            _parseIncomingMessage(data);
          }
        },
        onDone: () {
          _isConnected = false;
          onStatusChanged?.call(false, 'Disconnected from host');
        },
        onError: (err) {
          _isConnected = false;
          onStatusChanged?.call(false, 'Connection error: $err');
        },
      );
      
      // Mark connected
      _isConnected = true;
      onStatusChanged?.call(true, 'Connected to Device A!');
      return true;
    } catch (e) {
      _isConnected = false;
      onStatusChanged?.call(false, 'Failed to connect: $e');
      return false;
    }
  }

  void _parseIncomingMessage(String messageStr) {
    try {
      final jsonMap = jsonDecode(messageStr) as Map<String, dynamic>;
      final type = jsonMap['type'] as String?;

      if (type == 'frame') {
        final frame = FramePacket.fromBase64Json(jsonMap);
        onFrameReceived?.call(frame);
      } else if (type == 'gesture') {
        final gesture = GesturePacket.fromJson(jsonMap);
        onGestureReceived?.call(gesture);
      } else if (type == 'handshake') {
        final handshake = SystemHandshakePacket.fromJson(jsonMap);
        onHandshakeReceived?.call(handshake);
      }
    } catch (e) {
      // Ignore parse errors for corrupt frames
    }
  }

  void sendGesture(GesturePacket gesture) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(gesture.toJson()));
      } catch (e) {
        // Socket issue
      }
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    onStatusChanged?.call(false, 'Disconnected');
  }
}
