import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/models/mirror_protocol.dart';
import 'package:rndscreeningap/services/network_service.dart';

/// In-memory [IBroadcastService] that records everything it is asked to send.
class FakeBroadcastService implements IBroadcastService {
  FakeBroadcastService({this.hosting = true});

  bool hosting;
  final List<GesturePacket> gestures = [];
  final List<FramePacket> frames = [];

  @override
  bool get isHosting => hosting;

  @override
  Future<void> broadcastFrame(FramePacket frame) async => frames.add(frame);

  @override
  Future<void> broadcastGesture(GesturePacket gesture) async =>
      gestures.add(gesture);
}

/// Device A host without real sockets.
class FakeWebSocketServer extends WebSocketServerService {
  FakeWebSocketServer({this.startResult = true});

  final bool startResult;
  bool _hosting = false;
  int startCalls = 0;
  int? startedOnPort;
  bool stopped = false;

  @override
  bool get isHosting => _hosting;

  @override
  String get serverIp => '10.0.0.5';

  @override
  int get port => 8080;

  @override
  Future<bool> startServer({int port = 8080}) async {
    startCalls++;
    startedOnPort = port;
    _hosting = startResult;
    return startResult;
  }

  @override
  Future<void> stopServer() async {
    stopped = true;
    _hosting = false;
  }
}

/// Device B client without real sockets. Tests can push data into the screen
/// by invoking [onFrameReceived] / [onGestureReceived] / [onStatusChanged].
class FakeWebSocketClient extends WebSocketClientService {
  FakeWebSocketClient({this.succeed = true});

  final bool succeed;
  bool connected = false;
  final List<String> connectCalls = [];
  int disconnectCalls = 0;

  @override
  bool get isConnected => connected;

  @override
  Future<bool> connect(String ipAddress, {int port = 8080}) async {
    connectCalls.add(ipAddress);
    connected = succeed;
    onStatusChanged?.call(
      succeed,
      succeed ? 'Connected to Device A!' : 'Connection failed: fake',
    );
    return succeed;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    connected = false;
    // Like the real client, report asynchronously.
    await Future<void>.value();
    onStatusChanged?.call(false, 'Disconnected');
  }
}

/// A valid 1x1 PNG so `Image.memory` has something decodable.
final List<int> kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// Lets queued microtasks / stream events run on the real event loop.
Future<void> settle([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Gives a widget test a phone-sized logical surface (default is 800x600,
/// which makes several of these screens overflow).
void usePhoneSurface(WidgetTester tester,
    {Size size = const Size(400, 900)}) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
