import 'dart:convert';
import 'dart:typed_data';

enum TransportMode {
  webSocket,
  firebase,
}

abstract class IBroadcastService {
  bool get isHosting;
  Future<void> broadcastFrame(FramePacket frame);
  Future<void> broadcastGesture(GesturePacket gesture);
}

enum PointerAction {
  down,
  move,
  up,
  cancel,
  scroll,
}

class GesturePacket {
  final PointerAction action;
  final int pointerId;
  final double normalizedX; // 0.0 to 1.0
  final double normalizedY; // 0.0 to 1.0
  final double scrollDeltaX;
  final double scrollDeltaY;
  final int timestamp;
  final double deviceWidth;
  final double deviceHeight;

  GesturePacket({
    required this.action,
    required this.pointerId,
    required this.normalizedX,
    required this.normalizedY,
    this.scrollDeltaX = 0.0,
    this.scrollDeltaY = 0.0,
    required this.timestamp,
    this.deviceWidth = 1.0,
    this.deviceHeight = 1.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': 'gesture',
      'action': action.name,
      'pointerId': pointerId,
      'normalizedX': normalizedX,
      'normalizedY': normalizedY,
      'scrollDeltaX': scrollDeltaX,
      'scrollDeltaY': scrollDeltaY,
      'timestamp': timestamp,
      'deviceWidth': deviceWidth,
      'deviceHeight': deviceHeight,
    };
  }

  factory GesturePacket.fromJson(Map<String, dynamic> json) {
    return GesturePacket(
      action: PointerAction.values.firstWhere(
        (e) => e.name == json['action'],
        orElse: () => PointerAction.move,
      ),
      pointerId: json['pointerId'] as int? ?? 0,
      normalizedX: (json['normalizedX'] as num?)?.toDouble() ?? 0.0,
      normalizedY: (json['normalizedY'] as num?)?.toDouble() ?? 0.0,
      scrollDeltaX: (json['scrollDeltaX'] as num?)?.toDouble() ?? 0.0,
      scrollDeltaY: (json['scrollDeltaY'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      deviceWidth: (json['deviceWidth'] as num?)?.toDouble() ?? 1.0,
      deviceHeight: (json['deviceHeight'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

class FramePacket {
  final Uint8List imageBytes;
  final double aspectRatio;
  final int width;
  final int height;
  final int timestamp;
  final double currentFps;

  FramePacket({
    required this.imageBytes,
    required this.aspectRatio,
    required this.width,
    required this.height,
    required this.timestamp,
    this.currentFps = 30.0,
  });

  Map<String, dynamic> toJsonHeader() {
    return {
      'type': 'frame',
      'aspectRatio': aspectRatio,
      'width': width,
      'height': height,
      'timestamp': timestamp,
      'fps': currentFps,
      'bytesLength': imageBytes.length,
    };
  }

  String toBase64Json() {
    return jsonEncode({
      ...toJsonHeader(),
      'base64': base64Encode(imageBytes),
    });
  }

  factory FramePacket.fromBase64Json(Map<String, dynamic> json) {
    final base64Str = json['base64'] as String;
    return FramePacket(
      imageBytes: base64Decode(base64Str),
      aspectRatio: (json['aspectRatio'] as num?)?.toDouble() ?? 0.5,
      width: json['width'] as int? ?? 1080,
      height: json['height'] as int? ?? 1920,
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      currentFps: (json['fps'] as num?)?.toDouble() ?? 30.0,
    );
  }
}

class SystemHandshakePacket {
  final String deviceName;
  final String deviceRole; // 'broadcaster' or 'receiver'
  final double screenWidth;
  final double screenHeight;

  SystemHandshakePacket({
    required this.deviceName,
    required this.deviceRole,
    required this.screenWidth,
    required this.screenHeight,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': 'handshake',
      'deviceName': deviceName,
      'deviceRole': deviceRole,
      'screenWidth': screenWidth,
      'screenHeight': screenHeight,
    };
  }

  factory SystemHandshakePacket.fromJson(Map<String, dynamic> json) {
    return SystemHandshakePacket(
      deviceName: json['deviceName'] as String? ?? 'Unknown Device',
      deviceRole: json['deviceRole'] as String? ?? 'broadcaster',
      screenWidth: (json['screenWidth'] as num?)?.toDouble() ?? 1080.0,
      screenHeight: (json['screenHeight'] as num?)?.toDouble() ?? 1920.0,
    );
  }
}
