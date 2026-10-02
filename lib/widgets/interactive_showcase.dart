import 'package:flutter/material.dart';
import 'package:rndscreeningap/widgets/museum_poi.dart';

import '../theme/app_theme.dart';
import 'museum_map_view.dart';

class InteractiveShowcaseApp extends StatefulWidget {
  const InteractiveShowcaseApp({super.key});

  @override
  State<InteractiveShowcaseApp> createState() => _InteractiveShowcaseAppState();
}

class _InteractiveShowcaseAppState extends State<InteractiveShowcaseApp> {
  int _counter = 0;
  double _sliderValue = 50.0;
  bool _switchVal = true;
  int _selectedTabIndex = 0;
  final TextEditingController _textController = TextEditingController();

  // Drawing canvas points
  final List<Offset?> _drawingPoints = [];

  final List<Map<String, dynamic>> _feedItems = [
    {
      'title': 'Live Gesture Mirroring Active',
      'subtitle': 'Every tap, drag, and scroll on this device is streamed instantly to Device B.',
      'icon': Icons.touch_app_rounded,
      'color': AppColors.primary,
      'tag': 'SYSTEM',
    },
    {
      'title': 'Scroll Detection Demo',
      'subtitle': 'Try flinging up and down this scrollable list to test smooth scroll mirroring.',
      'icon': Icons.swap_vert_rounded,
      'color': AppColors.secondary,
      'tag': 'GESTURE',
    },
    {
      'title': 'Multi-Touch & Drag',
      'subtitle': 'Test sliders, drawing pads, and interactive buttons below.',
      'icon': Icons.gesture_rounded,
      'color': AppColors.accent,
      'tag': 'TOUCH',
    },
    {
      'title': 'High Frame-Rate Streamer',
      'subtitle': 'Captures RepaintBoundary frames and streams via direct local WebSockets.',
      'icon': Icons.speed_rounded,
      'color': AppColors.success,
      'tag': 'NETWORK',
    },
    {
      'title': 'Cross-Platform Compatibility',
      'subtitle': 'Supports Android, iOS mobile devices and Windows Desktop receivers.',
      'icon': Icons.devices_rounded,
      'color': AppColors.warning,
      'tag': 'CROSS-PLATFORM',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.screen_share_rounded, color: AppColors.primaryLight),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Interactive Demo Hub',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Device A (Broadcaster Mode)',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 4, backgroundColor: AppColors.success),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content Tabs
          Expanded(
            child: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildScrollFeedTab(),
                _buildControlsTab(),
                _buildDrawingPadTab(),
                MuseumMapView(pois: MuseumPoi.samplePois),
              ],
            ),
          ),

          // Bottom Navigation Bar
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.dynamic_feed_rounded, 'Feed'),
                _buildNavItem(1, Icons.tune_rounded, 'Touch Cntrl'),
                _buildNavItem(2, Icons.draw_rounded, 'Draw Canvas'),
                _buildNavItem(3, Icons.map_rounded, 'Museum Map'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
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

  Widget _buildScrollFeedTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _feedItems.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildBannerCard();
        }
        final item = _feedItems[index - 1];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (item['color'] as Color).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(item['icon'] as IconData, color: item['color'] as Color),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    item['title'] as String,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    item['tag'] as String,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                item['subtitle'] as String,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBannerCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.touch_app, color: Colors.white, size: 28),
              SizedBox(width: 10),
              Text(
                'Gesture Detector Ready',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Touch, tap, and scroll anywhere inside this area. Device B receives live screen frames and exact tap/scroll pointer positions in real-time!',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.primary,
            ),
            onPressed: () {
              setState(() => _counter++);
            },
            icon: const Icon(Icons.add),
            label: Text('Tap Counter: $_counter'),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Interactive Slider Dragging',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Value: ${_sliderValue.toStringAsFixed(1)}',
                    style: const TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
                  ),
                  Slider(
                    value: _sliderValue,
                    min: 0,
                    max: 100,
                    activeColor: AppColors.secondary,
                    onChanged: (val) => setState(() => _sliderValue = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Live Pointer Trail Effect'),
              subtitle: const Text('Renders touch spots on screen'),
              value: _switchVal,
              activeTrackColor: AppColors.primaryLight,
              onChanged: (val) => setState(() => _switchVal = val),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Live Text Input Test',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Type text to test live keyboard mirroring...',
                      prefixIcon: Icon(Icons.keyboard_rounded),
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

  Widget _buildDrawingPadTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.surface,
          child: Row(
            children: [
              const Icon(Icons.edit_rounded, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text(
                'Finger Drag & Draw Canvas',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _drawingPoints.clear()),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Clear'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            ],
          ),
        ),
        Expanded(
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _drawingPoints.add(details.localPosition);
              });
            },
            onPanEnd: (details) {
              setState(() {
                _drawingPoints.add(null);
              });
            },
            child: CustomPaint(
              painter: DrawingPainter(_drawingPoints),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset?> points;
  DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint..strokeWidth = 5.0);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) => true;
}
