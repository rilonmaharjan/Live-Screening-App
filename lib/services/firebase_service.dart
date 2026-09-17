import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/mirror_protocol.dart';

class FirebaseBroadcastService implements IBroadcastService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  bool _isHosting = false;
  bool _isConnected = false;
  String _channelId = 'live_stream';

  // Callbacks
  Function(FramePacket frame)? onFrameReceived;
  Function(GesturePacket gesture)? onGestureReceived;
  Function(bool connected, String status)? onStatusChanged;
  Function(String log)? onLog;
  Function(int count)? onListenerCountChanged;

  @override
  bool get isHosting => _isHosting;
  bool get isConnected => _isConnected;
  String get channelId => _channelId;

  /// Start acting as Device A Broadcaster
  Future<bool> startBroadcasting({String channelId = 'live_stream'}) async {
    _channelId = channelId.trim().isEmpty ? 'live_stream' : channelId.trim();
    try {
      _isHosting = true;
      _log('Initializing Firebase Cloud Broadcast on channel: $_channelId');

      await _firestore.collection('broadcasts').doc(_channelId).set({
        'status': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        'channelId': _channelId,
        'broadcasterPlatform': kIsWeb ? 'Web Browser' : defaultTargetPlatform.name,
      }, SetOptions(merge: true));

      _log('Firebase Broadcast active on channel "$_channelId"');
      onStatusChanged?.call(true, 'Firebase Stream Active ($_channelId)');
      return true;
    } catch (e) {
      _log('Error starting Firebase broadcast: $e');
      _isHosting = false;
      onStatusChanged?.call(false, 'Failed to start Firebase broadcast: $e');
      return false;
    }
  }

  /// Broadcast screen frame packet to Firebase Firestore
  @override
  Future<void> broadcastFrame(FramePacket frame) async {
    if (!_isHosting) return;
    try {
      final frameMap = {
        'base64': base64Encode(frame.imageBytes),
        'aspectRatio': frame.aspectRatio,
        'width': frame.width,
        'height': frame.height,
        'timestamp': frame.timestamp,
        'fps': frame.currentFps,
      };

      await _firestore.collection('broadcasts').doc(_channelId).set({
        'currentFrame': frameMap,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _log('Error uploading frame to Firestore: $e');
    }
  }

  /// Broadcast gesture packet to Firebase Firestore
  @override
  Future<void> broadcastGesture(GesturePacket gesture) async {
    if (!_isHosting) return;
    try {
      await _firestore.collection('broadcasts').doc(_channelId).set({
        'lastGesture': gesture.toJson(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _log('Error sending gesture to Firestore: $e');
    }
  }

  /// Connect Device B Receiver to Firebase Firestore stream
  Future<bool> connectToBroadcast({String channelId = 'live_stream'}) async {
    _channelId = channelId.trim().isEmpty ? 'live_stream' : channelId.trim();
    onStatusChanged?.call(false, 'Connecting to Firebase Channel "$_channelId"...');

    try {
      await disconnect();

      final docRef = _firestore.collection('broadcasts').doc(_channelId);

      _subscription = docRef.snapshots().listen(
        (snapshot) {
          if (!snapshot.exists) {
            _isConnected = false;
            onStatusChanged?.call(false, 'Channel "$_channelId" not found on Firebase');
            return;
          }

          if (!_isConnected) {
            _isConnected = true;
            onStatusChanged?.call(true, 'Connected to Firebase Channel "$_channelId"');
          }

          final data = snapshot.data();
          if (data == null) return;

          // Process Frame update
          if (data.containsKey('currentFrame') && data['currentFrame'] != null) {
            try {
              final frameData = Map<String, dynamic>.from(data['currentFrame'] as Map);
              final frame = FramePacket.fromBase64Json(frameData);
              onFrameReceived?.call(frame);
            } catch (e) {
              // Ignore invalid frame parsing
            }
          }

          // Process Gesture update
          if (data.containsKey('lastGesture') && data['lastGesture'] != null) {
            try {
              final gestureData = Map<String, dynamic>.from(data['lastGesture'] as Map);
              final gesture = GesturePacket.fromJson(gestureData);
              onGestureReceived?.call(gesture);
            } catch (e) {
              // Ignore invalid gesture parsing
            }
          }
        },
        onError: (err) {
          _isConnected = false;
          onStatusChanged?.call(false, 'Firebase Stream Error: $err');
        },
      );

      _isConnected = true;
      onStatusChanged?.call(true, 'Subscribed to Firebase Channel "$_channelId"');
      return true;
    } catch (e) {
      _isConnected = false;
      onStatusChanged?.call(false, 'Failed to connect to Firebase: $e');
      return false;
    }
  }

  /// Stop host broadcast
  Future<void> stopBroadcasting() async {
    _isHosting = false;
    try {
      await _firestore.collection('broadcasts').doc(_channelId).update({
        'status': 'ended',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Ignore cleanup error
    }
    _log('Broadcasting stopped on Firebase');
  }

  /// Disconnect receiver
  Future<void> disconnect() async {
    _isConnected = false;
    await _subscription?.cancel();
    _subscription = null;
    onStatusChanged?.call(false, 'Disconnected');
  }

  void _log(String msg) {
    onLog?.call(msg);
  }
}
