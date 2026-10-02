import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/services/frame_streamer.dart';

import '../helpers/fakes.dart';

void main() {
  group('FrameStreamerController state', () {
    late FakeBroadcastService service;
    late FrameStreamerController streamer;

    setUp(() {
      service = FakeBroadcastService();
      streamer = FrameStreamerController(broadcastService: service);
    });

    testWidgets('is idle by default', (tester) async {
      expect(streamer.isStreaming, isFalse);
      expect(streamer.currentFps, 0.0);
      expect(streamer.targetFps, 8);
    });

    testWidgets('startStreaming / stopStreaming toggle the state', (tester) async {
      streamer.startStreaming(fps: 10);
      expect(streamer.isStreaming, isTrue);
      expect(streamer.targetFps, 10);

      streamer.stopStreaming();
      expect(streamer.isStreaming, isFalse);
      expect(streamer.currentFps, 0.0);
    });

    testWidgets('startStreaming is ignored when already streaming', (tester) async {
      streamer.startStreaming(fps: 10);
      streamer.startStreaming(fps: 30);
      expect(streamer.targetFps, 10);

      streamer.stopStreaming(); // timers must not outlive the test body
    });

    testWidgets('updateFps changes the target and keeps streaming', (tester) async {
      streamer.startStreaming(fps: 8);
      streamer.updateFps(15);

      expect(streamer.targetFps, 15);
      expect(streamer.isStreaming, isTrue);

      streamer.stopStreaming();
    });

    testWidgets('updateFps while stopped only stores the new target', (tester) async {
      streamer.updateFps(20);
      expect(streamer.targetFps, 20);
      expect(streamer.isStreaming, isFalse);
    });

    testWidgets('does not broadcast when there is no attached RepaintBoundary',
        (tester) async {
      streamer.startStreaming(fps: 20);
      await tester.pump(const Duration(milliseconds: 300));
      streamer.triggerImmediateFrame();
      await tester.pump(const Duration(milliseconds: 100));
      streamer.stopStreaming();

      expect(service.frames, isEmpty);
    });

    testWidgets('triggerImmediateFrame is a no-op when not streaming',
        (tester) async {
      streamer.triggerImmediateFrame();
      await tester.pump();
      expect(service.frames, isEmpty);
    });
  });

  group('FrameStreamerController capture', () {
    testWidgets('captures the RepaintBoundary and broadcasts a PNG frame',
        (tester) async {
      final service = FakeBroadcastService();
      final streamer = FrameStreamerController(broadcastService: service);

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: streamer.repaintBoundaryKey,
              child: const SizedBox(
                width: 400,
                height: 800,
                child: ColoredBox(color: Colors.indigo),
              ),
            ),
          ),
        ),
      );

      // Image capture needs the real engine/event loop, not fake async.
      await tester.runAsync(() async {
        streamer.startStreaming(fps: 20);
        for (var i = 0; i < 60 && service.frames.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        streamer.stopStreaming();
      });

      expect(service.frames, isNotEmpty);
      final frame = service.frames.first;
      expect(frame.width, 400);
      expect(frame.height, 800);
      expect(frame.aspectRatio, closeTo(0.5, 1e-9));
      // PNG magic number.
      expect(frame.imageBytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    testWidgets('does not capture when the service is not hosting', (tester) async {
      final service = FakeBroadcastService(hosting: false);
      final streamer = FrameStreamerController(broadcastService: service);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: streamer.repaintBoundaryKey,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );

      await tester.runAsync(() async {
        streamer.startStreaming(fps: 20);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        streamer.stopStreaming();
      });

      expect(service.frames, isEmpty);
    });
  });
}
