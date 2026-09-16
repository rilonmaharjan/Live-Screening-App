import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/mirror_protocol.dart';
import '../theme/app_theme.dart';

class LiveGestureOverlay extends StatefulWidget {
  final Map<int, GesturePacket> activeGestures;
  final GesturePacket? latestScroll;
  final Size canvasSize;
  final bool showRipples;
  final bool showLabels;

  const LiveGestureOverlay({
    super.key,
    required this.activeGestures,
    this.latestScroll,
    required this.canvasSize,
    this.showRipples = true,
    this.showLabels = true,
  });

  @override
  State<LiveGestureOverlay> createState() => _LiveGestureOverlayState();
}

class _LiveGestureOverlayState extends State<LiveGestureOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return CustomPaint(
          size: widget.canvasSize,
          painter: GesturePainter(
            gestures: widget.activeGestures,
            latestScroll: widget.latestScroll,
            animValue: _animController.value,
            showRipples: widget.showRipples,
            showLabels: widget.showLabels,
          ),
        );
      },
    );
  }
}

class GesturePainter extends CustomPainter {
  final Map<int, GesturePacket> gestures;
  final GesturePacket? latestScroll;
  final double animValue;
  final bool showRipples;
  final bool showLabels;

  GesturePainter({
    required this.gestures,
    this.latestScroll,
    required this.animValue,
    required this.showRipples,
    required this.showLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    // 1. Draw Active Pointer Taps / Drags
    for (final entry in gestures.entries) {
      final gesture = entry.value;
      if (gesture.action == PointerAction.up || gesture.action == PointerAction.cancel) {
        continue;
      }

      final px = gesture.normalizedX * size.width;
      final py = gesture.normalizedY * size.height;
      final center = Offset(px, py);

      // Outer glowing pulse ring
      if (showRipples) {
        final rippleRadius = 24.0 + (animValue * 20.0);
        final rippleOpacity = (1.0 - animValue).clamp(0.0, 1.0);
        final ripplePaint = Paint()
          ..color = AppColors.accent.withValues(alpha: rippleOpacity * 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0;

        canvas.drawCircle(center, rippleRadius, ripplePaint);

        // Secondary inner pulse
        final innerRippleRadius = 12.0 + (animValue * 10.0);
        final innerRipplePaint = Paint()
          ..color = AppColors.secondary.withValues(alpha: rippleOpacity * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;

        canvas.drawCircle(center, innerRippleRadius, innerRipplePaint);
      }

      // Solid Touch Core Dot
      final coreGlowPaint = Paint()
        ..color = AppColors.accent.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, 16.0, coreGlowPaint);

      final corePaint = Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 10.0, corePaint);

      final centerWhitePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 4.0, centerWhitePaint);

      // Touch position text label
      if (showLabels) {
        final textSpan = TextSpan(
          text: 'P${gesture.pointerId} (${(gesture.normalizedX * 100).toStringAsFixed(0)}%, ${(gesture.normalizedY * 100).toStringAsFixed(0)}%)',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 4,
              ),
            ],
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(px + 16, py - 20));
      }
    }

    // 2. Draw Scroll Vector Overlay if active
    if (latestScroll != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final timeDiff = nowMs - latestScroll!.timestamp;

      // Display scroll indicator for 800ms after event
      if (timeDiff < 800) {
        final fadeOpacity = ((800 - timeDiff) / 800.0).clamp(0.0, 1.0);
        final px = latestScroll!.normalizedX * size.width;
        final py = latestScroll!.normalizedY * size.height;
        final center = Offset(px, py);

        final dy = latestScroll!.scrollDeltaY;
        final dx = latestScroll!.scrollDeltaX;

        // Draw scroll direction arrow
        final arrowLength = math.min(60.0, math.max(25.0, math.sqrt(dx * dx + dy * dy)));
        final angle = math.atan2(dy, dx);

        final endPoint = Offset(
          center.dx + arrowLength * math.cos(angle),
          center.dy + arrowLength * math.sin(angle),
        );

        final linePaint = Paint()
          ..color = AppColors.secondary.withValues(alpha: fadeOpacity)
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(center, endPoint, linePaint);

        // Arrow head
        final arrowHeadSize = 10.0;
        final leftWing = Offset(
          endPoint.dx - arrowHeadSize * math.cos(angle - math.pi / 6),
          endPoint.dy - arrowHeadSize * math.sin(angle - math.pi / 6),
        );
        final rightWing = Offset(
          endPoint.dx - arrowHeadSize * math.cos(angle + math.pi / 6),
          endPoint.dy - arrowHeadSize * math.sin(angle + math.pi / 6),
        );

        final path = Path()
          ..moveTo(endPoint.dx, endPoint.dy)
          ..lineTo(leftWing.dx, leftWing.dy)
          ..lineTo(rightWing.dx, rightWing.dy)
          ..close();

        final arrowPaint = Paint()
          ..color = AppColors.secondary.withValues(alpha: fadeOpacity)
          ..style = PaintingStyle.fill;

        canvas.drawPath(path, arrowPaint);

        // Scroll text badge
        if (showLabels) {
          final scrollSpan = TextSpan(
            text: 'SCROLL dy:${dy.toStringAsFixed(1)}',
            style: TextStyle(
              color: AppColors.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              backgroundColor: Colors.black.withValues(alpha: 0.6 * fadeOpacity),
            ),
          );
          final tp = TextPainter(text: scrollSpan, textDirection: TextDirection.ltr);
          tp.layout();
          tp.paint(canvas, Offset(center.dx - 40, center.dy - 30));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant GesturePainter oldDelegate) => true;
}
