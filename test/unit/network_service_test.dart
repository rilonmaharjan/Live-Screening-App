// NOTE: this file intentionally contains no testWidgets(). Using plain test()
// keeps the TestWidgetsFlutterBinding (which stubs out dart:io HTTP) from being
// installed, so real loopback sockets work.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/models/mirror_protocol.dart';
import 'package:rndscreeningap/services/network_service.dart';

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

GesturePacket _gesture({
  PointerAction action = PointerAction.down,
  int id = 1,
  double x = 0.5,
  double y = 0.5,
}) =>
    GesturePacket(
      action: action,
      pointerId: id,
      normalizedX: x,
      normalizedY: y,
      timestamp: 1,
    );

const _timeout = Duration(seconds: 5);

void main() {
  group('IPHelper', () {
    test('getLocalIPAddress returns a parseable IPv4 address', () async {
      final ip = await IPHelper.getLocalIPAddress();
      final parsed = InternetAddress.tryParse(ip);

      expect(parsed, isNotNull);
      expect(parsed!.type, InternetAddressType.IPv4);
    });
  });

  group('WebSocketServerService', () {
    late WebSocketServerService server;
    late int port;

    setUp(() async {
      server = WebSocketServerService();
      port = await _freePort();
    });

    tearDown(() => server.stopServer());

    test('is not hosting before it is started', () {
      expect(server.isHosting, isFalse);
      expect(server.clientCount, 0);
    });

    test('startServer begins hosting on the requested port', () async {
      final logs = <String>[];
      server.onLog = logs.add;

      final ok = await server.startServer(port: port);

      expect(ok, isTrue);
      expect(server.isHosting, isTrue);
      expect(server.port, port);
      expect(logs.any((l) => l.contains('Server started')), isTrue);
    });

    test('startServer fails gracefully when the port is already taken', () async {
      final blocker = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      addTearDown(blocker.close);
      final logs = <String>[];
      server.onLog = logs.add;

      final ok = await server.startServer(port: port);

      expect(ok, isFalse);
      expect(server.isHosting, isFalse);
      expect(logs.any((l) => l.contains('Failed to start server')), isTrue);
    });

    test('serves the built-in HTML web viewer over plain HTTP', () async {
      await server.startServer(port: port);

      final client = HttpClient();
      addTearDown(client.close);
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
      final response = await request.close();
      final body = await utf8.decodeStream(response);

      expect(response.statusCode, HttpStatus.ok);
      expect(response.headers.contentType?.mimeType, 'text/html');
      expect(body, contains('Device B Web Viewer'));
      expect(body, contains('new WebSocket('));
    });

    test('stopServer stops hosting and closes connected clients', () async {
      await server.startServer(port: port);
      final socket = await WebSocket.connect('ws://127.0.0.1:$port');
      final closed = Completer<void>();
      socket.listen((_) {}, onDone: closed.complete);
      await _waitFor(() => server.clientCount == 1);

      await server.stopServer();

      expect(server.isHosting, isFalse);
      expect(server.clientCount, 0);
      await closed.future.timeout(_timeout);
    });

    test('broadcast methods are no-ops when no client is connected', () async {
      await server.startServer(port: port);
      await server.broadcastGesture(_gesture());
      await server.broadcastFrame(FramePacket(
        imageBytes: Uint8List(4),
        aspectRatio: 1,
        width: 1,
        height: 1,
        timestamp: 1,
      ));
      // Nothing to assert beyond "did not throw".
      expect(server.clientCount, 0);
    });

    test('tracks client connects and disconnects', () async {
      final counts = <int>[];
      server.onClientCountChanged = counts.add;
      await server.startServer(port: port);

      final a = await WebSocket.connect('ws://127.0.0.1:$port');
      await _waitFor(() => server.clientCount == 1);
      final b = await WebSocket.connect('ws://127.0.0.1:$port');
      await _waitFor(() => server.clientCount == 2);
      await a.close();
      await _waitFor(() => server.clientCount == 1);
      await b.close();
      await _waitFor(() => server.clientCount == 0);

      expect(counts, [1, 2, 1, 0]);
    });

    test('broadcasts gestures to every connected client', () async {
      await server.startServer(port: port);
      final a = await WebSocket.connect('ws://127.0.0.1:$port');
      final b = await WebSocket.connect('ws://127.0.0.1:$port');
      addTearDown(a.close);
      addTearDown(b.close);
      await _waitFor(() => server.clientCount == 2);

      final fa = a.first.timeout(_timeout);
      final fb = b.first.timeout(_timeout);
      await server.broadcastGesture(_gesture(id: 4, x: 0.2, y: 0.8));

      for (final raw in await Future.wait([fa, fb])) {
        final json = jsonDecode(raw as String) as Map<String, dynamic>;
        expect(json['type'], 'gesture');
        expect(json['pointerId'], 4);
        expect(json['normalizedX'], 0.2);
        expect(json['normalizedY'], 0.8);
      }
    });

    test('receives gestures sent by a client and ignores malformed data',
        () async {
      final received = <GesturePacket>[];
      server.onGestureReceived = received.add;
      await server.startServer(port: port);
      final socket = await WebSocket.connect('ws://127.0.0.1:$port');
      addTearDown(socket.close);
      await _waitFor(() => server.clientCount == 1);

      socket.add('this is not json');
      socket.add(jsonEncode({'type': 'unknown'}));
      socket.add(jsonEncode(_gesture(action: PointerAction.up, id: 8).toJson()));

      await _waitFor(() => received.isNotEmpty);
      expect(received, hasLength(1));
      expect(received.single.action, PointerAction.up);
      expect(received.single.pointerId, 8);
    });
  });

  group('WebSocketClientService.connect validation', () {
    late WebSocketClientService client;
    late List<(bool, String)> statuses;

    setUp(() {
      client = WebSocketClientService();
      statuses = [];
      client.onStatusChanged = (c, s) => statuses.add((c, s));
    });

    test('rejects an empty address', () async {
      expect(await client.connect('   '), isFalse);
      expect(client.isConnected, isFalse);
      expect(statuses.single.$2, contains('valid IP'));
    });

    test('rejects an address that ends with a dot (unfinished IP)', () async {
      expect(await client.connect('192.168.1.'), isFalse);
      expect(statuses.single.$2, contains('valid IP'));
    });

    test('reports a failure when the host is unreachable', () async {
      final port = await _freePort(); // nothing is listening here

      final ok = await client.connect('127.0.0.1', port: port);

      expect(ok, isFalse);
      expect(client.isConnected, isFalse);
      expect(statuses.last.$1, isFalse);
      expect(statuses.last.$2, contains('Connection failed'));
    });
  });

  group('WebSocketClientService <-> WebSocketServerService (loopback)', () {
    late WebSocketServerService server;
    late WebSocketClientService client;
    late int port;

    setUp(() async {
      server = WebSocketServerService();
      client = WebSocketClientService();
      port = await _freePort();
      await server.startServer(port: port);
    });

    tearDown(() async {
      await client.disconnect();
      await server.stopServer();
    });

    Future<void> connectClient([String? address]) async {
      final ok = await client.connect(address ?? '127.0.0.1:$port');
      expect(ok, isTrue);
      await _waitFor(() => server.clientCount == 1);
    }

    test('connects, reports status and parses host:port', () async {
      final statuses = <(bool, String)>[];
      client.onStatusChanged = (c, s) => statuses.add((c, s));

      await connectClient();

      expect(client.isConnected, isTrue);
      expect(client.targetIp, '127.0.0.1');
      expect(statuses.first.$2, contains('Connecting to ws://127.0.0.1:$port'));
      expect(statuses.last, (true, 'Connected to Device A!'));
    });

    test('accepts a pasted URL with scheme', () async {
      await connectClient('ws://127.0.0.1:$port');
      expect(client.isConnected, isTrue);
      expect(client.targetIp, '127.0.0.1');
    });

    test('delivers server gestures to the client', () async {
      final received = Completer<GesturePacket>();
      client.onGestureReceived = received.complete;
      await connectClient();

      await server.broadcastGesture(_gesture(action: PointerAction.move, id: 2, x: 0.3, y: 0.6));

      final gesture = await received.future.timeout(_timeout);
      expect(gesture.action, PointerAction.move);
      expect(gesture.pointerId, 2);
      expect(gesture.normalizedX, 0.3);
      expect(gesture.normalizedY, 0.6);
    });

    test('delivers server frames to the client with bytes intact', () async {
      final received = Completer<FramePacket>();
      client.onFrameReceived = received.complete;
      await connectClient();

      final bytes = Uint8List.fromList(List<int>.generate(256, (i) => i));
      await server.broadcastFrame(FramePacket(
        imageBytes: bytes,
        aspectRatio: 0.5,
        width: 540,
        height: 1080,
        timestamp: 77,
        currentFps: 9,
      ));

      final frame = await received.future.timeout(_timeout);
      expect(frame.imageBytes, bytes);
      expect(frame.width, 540);
      expect(frame.height, 1080);
      expect(frame.timestamp, 77);
      expect(frame.currentFps, 9);
    });

    test('delivers handshake packets to the client', () async {
      final received = Completer<SystemHandshakePacket>();
      client.onHandshakeReceived = received.complete;
      await connectClient();

      server.broadcast(jsonEncode(SystemHandshakePacket(
        deviceName: 'Host',
        deviceRole: 'broadcaster',
        screenWidth: 100,
        screenHeight: 200,
      ).toJson()));

      final handshake = await received.future.timeout(_timeout);
      expect(handshake.deviceName, 'Host');
      expect(handshake.screenHeight, 200);
    });

    test('ignores corrupt frames and keeps working afterwards', () async {
      final received = Completer<GesturePacket>();
      client.onGestureReceived = received.complete;
      await connectClient();

      server.broadcast('{{{ not json');
      server.broadcast(jsonEncode({'type': 'frame'})); // missing base64 -> throws
      await server.broadcastGesture(_gesture(id: 3));

      expect((await received.future.timeout(_timeout)).pointerId, 3);
      expect(client.isConnected, isTrue);
    });

    test('client gestures reach the server', () async {
      final received = Completer<GesturePacket>();
      server.onGestureReceived = received.complete;
      await connectClient();

      client.sendGesture(_gesture(action: PointerAction.scroll, id: 6));

      final gesture = await received.future.timeout(_timeout);
      expect(gesture.action, PointerAction.scroll);
      expect(gesture.pointerId, 6);
    });

    test('sendGesture before connecting does nothing', () {
      client.sendGesture(_gesture()); // must not throw
      expect(client.isConnected, isFalse);
    });

    test('disconnect updates state, status and the server client count', () async {
      final statuses = <(bool, String)>[];
      await connectClient();
      client.onStatusChanged = (c, s) => statuses.add((c, s));

      await client.disconnect();

      expect(client.isConnected, isFalse);
      expect(statuses.last, (false, 'Disconnected'));
      await _waitFor(() => server.clientCount == 0);
    });

    test('client notices when the host goes away', () async {
      final statuses = <(bool, String)>[];
      await connectClient();
      client.onStatusChanged = (c, s) => statuses.add((c, s));

      await server.stopServer();

      await _waitFor(() => !client.isConnected);
      expect(statuses.last.$1, isFalse);
      expect(statuses.last.$2, anyOf(contains('Disconnected'), contains('error')));
    });
  });

}

/// Polls [condition] on the real event loop until true or [_timeout] elapses.
Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(_timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition not met within $_timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
