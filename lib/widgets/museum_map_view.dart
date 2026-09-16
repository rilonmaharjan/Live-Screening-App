import 'package:flutter/material.dart';

import '../models/museum_item.dart';
import '../theme/app_theme.dart';

class MuseumMapView extends StatefulWidget {
  const MuseumMapView({super.key});

  @override
  State<MuseumMapView> createState() => _MuseumMapViewState();
}

class _MuseumMapViewState extends State<MuseumMapView> with SingleTickerProviderStateMixin {
  MuseumItem? _selectedItem;
  MuseumItem? _detailedItem;
  bool _showRightColumn = false;
  late AnimationController _columnAnimController;
  late Animation<Offset> _columnSlideAnimation;

  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _columnAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _columnSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _columnAnimController,
      curve: Curves.easeOutCubic,
    ));

    // Default select Hospital first so user immediately sees interactive popup experience
    _selectedItem = MuseumItem.sampleItems.first;
  }

  @override
  void dispose() {
    _columnAnimController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _openDetails(MuseumItem item) {
    setState(() {
      _detailedItem = item;
      _showRightColumn = true;
    });
    _columnAnimController.forward();
  }

  void _closeDetails() {
    _columnAnimController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showRightColumn = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = MuseumItem.sampleItems;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 1. MAIN INTERACTIVE MAP AREA WITH PINS & ANCHORED POPUP (FULL SCREEN)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // Tap on empty space closes info popup if open
                if (_selectedItem != null && !_showRightColumn) {
                  setState(() => _selectedItem = null);
                }
              },
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.8,
                maxScale: 3.5,
                boundaryMargin: const EdgeInsets.all(200),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final mapWidth = constraints.maxWidth;
                    final mapHeight = constraints.maxHeight;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Full Screen Base Map Image Asset with Fallback
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Color(0xFF131924),
                            ),
                            child: Image.asset(
                              'assets/images/museum_map.png',
                              fit: BoxFit.cover,
                              width: mapWidth,
                              height: mapHeight,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildFallbackMapBackground();
                              },
                            ),
                          ),
                        ),

                        // Map Zone Overlay Graphics & Grid Lines
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primaryLight.withValues(alpha: 0.2),
                                  width: 1,
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: 0.2),
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.3),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Interactive Location Pins
                        ...items.map((item) {
                          final posX = item.dx * mapWidth;
                          final posY = item.dy * mapHeight;
                          final isSelected = _selectedItem?.id == item.id;

                          return Positioned(
                            left: posX - 24,
                            top: posY - 48,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedItem = item;
                                });
                              },
                              child: AnimatedScale(
                                scale: isSelected ? 1.25 : 1.0,
                                duration: const Duration(milliseconds: 200),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Pin Badge with Icon
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? Colors.white : item.color,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: item.color.withValues(alpha: 0.6),
                                            blurRadius: isSelected ? 14 : 6,
                                            spreadRadius: isSelected ? 3 : 1,
                                          ),
                                        ],
                                        border: Border.all(
                                          color: isSelected ? item.color : Colors.white,
                                          width: 2.5,
                                        ),
                                      ),
                                      child: Icon(
                                        item.icon,
                                        size: 20,
                                        color: isSelected ? item.color : Colors.white,
                                      ),
                                    ),

                                    // Pin Pointer Tail
                                    CustomPaint(
                                      size: const Size(12, 8),
                                      painter: _PinTailPainter(
                                        isSelected ? Colors.white : item.color,
                                      ),
                                    ),

                                    // Label Badge
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.85),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: item.color.withValues(alpha: 0.6)),
                                      ),
                                      child: Text(
                                        item.name.split(' ').first,
                                        style: TextStyle(
                                          color: item.color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),

                        // ANCHORED INFO WINDOW POPUP ABOVE CLICKED ITEM
                        if (_selectedItem != null)
                          _buildAnchoredInfoWindow(
                            _selectedItem!,
                            mapWidth,
                            mapHeight,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),

          // 2. COMPACT FLOATING TOP MENU UI OVERLAY
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                children: [

                  // Horizontal Scrollable Quick Zone Selectors
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: items.map((item) {
                          final isSelected = _selectedItem?.id == item.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => setState(() => _selectedItem = item),
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? item.color
                                      : AppColors.surfaceLight.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.white
                                        : item.color.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(item.icon, size: 14, color: isSelected ? Colors.white : item.color),
                                    const SizedBox(width: 4),
                                    Text(
                                      item.name.split(' ').first,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white : AppColors.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Reset Map Zoom Center Button
                  IconButton(
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(6),
                    icon: const Icon(Icons.center_focus_strong_rounded, size: 18, color: AppColors.primaryLight),
                    tooltip: 'Reset View',
                    onPressed: () => _transformationController.value = Matrix4.identity(),
                  ),
                ],
              ),
            ),
          ),

          // 3. GOOGLE MAPS STYLE RIGHT SIDE DETAILED COLUMN / DRAWER
          if (_showRightColumn && _detailedItem != null)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: MediaQuery.of(context).size.width > 700 ? 420 : MediaQuery.of(context).size.width * 0.85,
              child: SlideTransition(
                position: _columnSlideAnimation,
                child: _buildGoogleStyleDetailColumn(_detailedItem!),
              ),
            ),
        ],
      ),
    );
  }

  // ANCHORED INFO WINDOW POPUP
  Widget _buildAnchoredInfoWindow(MuseumItem item, double mapWidth, double mapHeight) {
    final posX = item.dx * mapWidth;
    final posY = item.dy * mapHeight;

    // Constrain popup horizontally so it doesn't overflow edge of map
    double popupLeft = posX - 140;
    if (popupLeft < 10) popupLeft = 10;
    if (popupLeft + 280 > mapWidth - 10) popupLeft = mapWidth - 290;

    double popupTop = posY - 185;
    if (popupTop < 10) popupTop = posY + 50; // Show below if too near top edge

    return Positioned(
      left: popupLeft,
      top: popupTop,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 280,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2430),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: item.color.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: item.color.withValues(alpha: 0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Category Badge & Close Button
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: item.color.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      item.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: item.color,
                      ),
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _selectedItem = null),
                    child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Title with Icon
              Row(
                children: [
                  Icon(item.icon, color: item.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Short Description
              Text(
                item.shortDescription,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Action Buttons Row: Read More Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                      const SizedBox(width: 3),
                      Text(
                        '${item.rating}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        ' (${item.reviewCount})',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _openDetails(item),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: item.color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    icon: const Text(
                      'Read More',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    label: const Icon(Icons.arrow_forward_rounded, size: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // GOOGLE MAPS STYLE RIGHT SIDE DETAILED COLUMN
  Widget _buildGoogleStyleDetailColumn(MuseumItem item) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 25,
            spreadRadius: 5,
          ),
        ],
        border: Border(
          left: BorderSide(color: item.color.withValues(alpha: 0.4), width: 2),
        ),
      ),
      child: Column(
        children: [
          // 1. Top Cover Header Banner with Action Buttons & Close
          Stack(
            children: [
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [item.color.withValues(alpha: 0.8), AppColors.surface],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Icon(
                    item.icon,
                    size: 72,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.4),
                        Colors.transparent,
                        AppColors.surface,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // Title & Category Badge over Banner
              Positioned(
                bottom: 12,
                left: 16,
                right: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.category.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),

              // Close Button ('X')
              Positioned(
                top: 12,
                right: 12,
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.6),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: _closeDetails,
                  ),
                ),
              ),
            ],
          ),

          // 2. Scrollable Body Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Star Rating & Review Header Row
                Row(
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
                    const SizedBox(width: 4),
                    Text(
                      '${item.rating}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${item.reviewCount} Google reviews)',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Quick Action Buttons Row (Google Maps style)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildGoogleActionButton(Icons.directions_rounded, 'Directions', item.color),
                    _buildGoogleActionButton(Icons.call_rounded, 'Call Info', item.color),
                    _buildGoogleActionButton(Icons.headphones_rounded, 'Audio Guide', item.color),
                    _buildGoogleActionButton(Icons.bookmark_border_rounded, 'Save', item.color),
                    _buildGoogleActionButton(Icons.share_rounded, 'Share', item.color),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),

                // Location & Hours Cards
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.surfaceLight,
                    child: Icon(Icons.layers_rounded, color: item.color),
                  ),
                  title: const Text('Floor Level', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(item.floorLevel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.surfaceLight,
                    child: Icon(Icons.access_time_rounded, color: AppColors.success),
                  ),
                  title: const Text('Operating Hours', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(item.openingHours, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                const Divider(),

                // Full Detailed Description Section
                const Text(
                  'About this Attraction',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.fullDescription,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),

                // Key Highlights List
                const Text(
                  'Key Highlights',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                ...item.highlights.map(
                  (hl) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.check_circle_rounded, color: item.color, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hl,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),

                // Visitor Reviews Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Visitor Reviews',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Write Review', style: TextStyle(color: AppColors.primaryLight)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...item.reviews.map(
                  (rev) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: item.color.withValues(alpha: 0.3),
                              child: Text(
                                rev['user']![0],
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: item.color),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              rev['user']!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                            ),
                            const Spacer(),
                            const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                            Text(
                              rev['rating']!,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          rev['comment']!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),

          // Bottom Action Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Navigating to ${item.name}...'),
                      backgroundColor: item.color,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: item.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Start AR Navigation to Zone', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleActionButton(IconData icon, String label, Color color) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackMapBackground() {
    return Container(
      color: const Color(0xFF1B222E),
      child: CustomPaint(
        painter: _MapCanvasBackgroundPainter(),
      ),
    );
  }
}

class _PinTailPainter extends CustomPainter {
  final Color color;
  _PinTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _MapCanvasBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    const gridStep = 40.0;
    for (double x = 0; x < size.width; x += gridStep) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridStep) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final pathPaint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.25)
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.3)
      ..lineTo(size.width * 0.5, size.height * 0.45)
      ..lineTo(size.width * 0.75, size.height * 0.25)
      ..moveTo(size.width * 0.5, size.height * 0.45)
      ..lineTo(size.width * 0.25, size.height * 0.65)
      ..lineTo(size.width * 0.78, size.height * 0.68)
      ..moveTo(size.width * 0.25, size.height * 0.65)
      ..lineTo(size.width * 0.5, size.height * 0.85);

    canvas.drawPath(path, pathPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
