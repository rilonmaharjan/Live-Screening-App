import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/models/mirror_protocol.dart';

void main() {
  group('GesturePacket', () {
    test('toJson contains all fields and the gesture type tag', () {
      final packet = GesturePacket(
        action: PointerAction.scroll,
        pointerId: 7,
        normalizedX: 0.25,
        normalizedY: 0.75,
        scrollDeltaX: 1.5,
        scrollDeltaY: -20,
        timestamp: 123456,
        deviceWidth: 400,
        deviceHeight: 800,
      );

      expect(packet.toJson(), {
        'type': 'gesture',
        'action': 'scroll',
        'pointerId': 7,
        'normalizedX': 0.25,
        'normalizedY': 0.75,
        'scrollDeltaX': 1.5,
        'scrollDeltaY': -20,
        'timestamp': 123456,
        'deviceWidth': 400,
        'deviceHeight': 800,
      });
    });

    test('fromJson(toJson()) round-trips for every PointerAction', () {
      for (final action in PointerAction.values) {
        final original = GesturePacket(
          action: action,
          pointerId: 3,
          normalizedX: 0.1,
          normalizedY: 0.9,
          scrollDeltaX: 2,
          scrollDeltaY: 4,
          timestamp: 99,
          deviceWidth: 360,
          deviceHeight: 640,
        );
        // Go through a real JSON string, like the wire does.
        final decoded = GesturePacket.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        );

        expect(decoded.action, action);
        expect(decoded.pointerId, 3);
        expect(decoded.normalizedX, 0.1);
        expect(decoded.normalizedY, 0.9);
        expect(decoded.scrollDeltaX, 2);
        expect(decoded.scrollDeltaY, 4);
        expect(decoded.timestamp, 99);
        expect(decoded.deviceWidth, 360);
        expect(decoded.deviceHeight, 640);
      }
    });

    test('fromJson applies defaults for missing fields', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final packet = GesturePacket.fromJson(<String, dynamic>{});
      final after = DateTime.now().millisecondsSinceEpoch;

      expect(packet.action, PointerAction.move);
      expect(packet.pointerId, 0);
      expect(packet.normalizedX, 0.0);
      expect(packet.normalizedY, 0.0);
      expect(packet.scrollDeltaX, 0.0);
      expect(packet.scrollDeltaY, 0.0);
      expect(packet.deviceWidth, 1.0);
      expect(packet.deviceHeight, 1.0);
      expect(packet.timestamp, inInclusiveRange(before, after));
    });

    test('fromJson falls back to move for an unknown action', () {
      final packet = GesturePacket.fromJson({'action': 'teleport'});
      expect(packet.action, PointerAction.move);
    });

    test('fromJson accepts ints where doubles are expected', () {
      final packet = GesturePacket.fromJson({
        'normalizedX': 1,
        'normalizedY': 0,
        'scrollDeltaY': 5,
      });
      expect(packet.normalizedX, 1.0);
      expect(packet.normalizedY, 0.0);
      expect(packet.scrollDeltaY, 5.0);
    });
  });

  group('FramePacket', () {
    final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));

    FramePacket makeFrame() => FramePacket(
          imageBytes: bytes,
          aspectRatio: 0.5625,
          width: 1080,
          height: 1920,
          timestamp: 42,
          currentFps: 12.5,
        );

    test('toJsonHeader describes the frame without the raw bytes', () {
      final header = makeFrame().toJsonHeader();

      expect(header['type'], 'frame');
      expect(header['aspectRatio'], 0.5625);
      expect(header['width'], 1080);
      expect(header['height'], 1920);
      expect(header['timestamp'], 42);
      expect(header['fps'], 12.5);
      expect(header['bytesLength'], 64);
      expect(header.containsKey('base64'), isFalse);
    });

    test('toBase64Json embeds the bytes as base64', () {
      final json = jsonDecode(makeFrame().toBase64Json()) as Map<String, dynamic>;
      expect(json['type'], 'frame');
      expect(base64Decode(json['base64'] as String), bytes);
    });

    test('fromBase64Json(toBase64Json()) round-trips', () {
      final json = jsonDecode(makeFrame().toBase64Json()) as Map<String, dynamic>;
      final decoded = FramePacket.fromBase64Json(json);

      expect(decoded.imageBytes, bytes);
      expect(decoded.aspectRatio, 0.5625);
      expect(decoded.width, 1080);
      expect(decoded.height, 1920);
      expect(decoded.timestamp, 42);
      expect(decoded.currentFps, 12.5);
    });

    test('fromBase64Json applies defaults when only base64 is present', () {
      final decoded = FramePacket.fromBase64Json({'base64': base64Encode(bytes)});

      expect(decoded.imageBytes, bytes);
      expect(decoded.aspectRatio, 0.5);
      expect(decoded.width, 1080);
      expect(decoded.height, 1920);
      expect(decoded.currentFps, 30.0);
    });

    test('fromBase64Json throws when base64 is missing', () {
      expect(() => FramePacket.fromBase64Json(<String, dynamic>{}), throwsA(anything));
    });
  });

  group('SystemHandshakePacket', () {
    test('round-trips through JSON', () {
      final packet = SystemHandshakePacket(
        deviceName: 'Pixel 8',
        deviceRole: 'receiver',
        screenWidth: 412,
        screenHeight: 915,
      );
      final json = packet.toJson();
      expect(json['type'], 'handshake');

      final decoded = SystemHandshakePacket.fromJson(json);
      expect(decoded.deviceName, 'Pixel 8');
      expect(decoded.deviceRole, 'receiver');
      expect(decoded.screenWidth, 412);
      expect(decoded.screenHeight, 915);
    });

    test('fromJson applies defaults', () {
      final decoded = SystemHandshakePacket.fromJson(<String, dynamic>{});
      expect(decoded.deviceName, 'Unknown Device');
      expect(decoded.deviceRole, 'broadcaster');
      expect(decoded.screenWidth, 1080.0);
      expect(decoded.screenHeight, 1920.0);
    });
  });

  test('TransportMode and PointerAction expose the expected values', () {
    expect(TransportMode.values, [TransportMode.webSocket, TransportMode.firebase]);
    expect(PointerAction.values.map((e) => e.name),
        ['down', 'move', 'up', 'cancel', 'scroll']);
  });
}
