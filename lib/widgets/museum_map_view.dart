import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'museum_poi.dart';

class MuseumMapView extends StatefulWidget {
  final List<MuseumPoi> pois;

  const MuseumMapView({
    super.key,
    required this.pois,
  });

  @override
  State<MuseumMapView> createState() => _MuseumMapViewState();
}

class _MuseumMapViewState extends State<MuseumMapView> with TickerProviderStateMixin {
  MuseumPoi? _selectedPoi;
  bool _showSidePanel = false;

  // Zoom & Pan Controller
  final TransformationController _transformationController = TransformationController();
  AnimationController? _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;

  // Side Panel Animation Controller
  late AnimationController _panelAnimationController;
  late Animation<Offset> _panelSlideAnimation;

  @override
  void initState() {
    super.initState();
    _panelAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _panelAnimationController,
      curve: Curves.easeOutCubic,
    ));

    // Rebuild top-level info callout overlay on matrix zoom/pan
    _transformationController.addListener(_onTransformationChanged);
  }

  void _onTransformationChanged() {
    if (_selectedPoi != null && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _zoomAnimationController?.dispose();
    _panelAnimationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _selectPoi(MuseumPoi poi, Size viewportSize, double mapWidth, double mapHeight) {
    if (_zoomAnimationController?.isAnimating == true) {
      _zoomAnimationController!.stop();
    }
    setState(() {
      _selectedPoi = poi;
    });
    _zoomToPoi(poi, viewportSize, mapWidth, mapHeight);
  }

  // Smooth camera panning that places ANY pin directly in the visible center of the screen
  void _zoomToPoi(MuseumPoi poi, Size viewportSize, double mapWidth, double mapHeight) {
    if (viewportSize.width == 0 || viewportSize.height == 0) return;

    final double mapLeftOffset = (viewportSize.width - mapWidth) / 2;
    final double mapTopOffset = (viewportSize.height - mapHeight) / 2;

    final pinX = poi.dx * mapWidth;
    final pinY = poi.dy * mapHeight;

    // Responsive target scale factor
    final bool isTablet = viewportSize.width >= 600;
    final double targetScale = isTablet ? 1.6 : (viewportSize.width < 500 ? 1.85 : 1.6);

    // Calculate dynamic horizontal center:
    // If the side panel is open, center the pin in the remaining UNCOVERED left area of the screen
    double targetScreenX = viewportSize.width / 2;
    if (_showSidePanel) {
      final double panelWidth = isTablet ? 380.0 : (viewportSize.width * 0.85);
      final double visibleMapWidth = viewportSize.width - panelWidth;
      targetScreenX = math.max(visibleMapWidth / 2, 70.0);
    }

    final double targetScreenY = viewportSize.height * 0.44;

    // Exact matrix translation to center the pin on screen
    final double translateX = targetScreenX - mapLeftOffset - (pinX * targetScale);
    final double translateY = targetScreenY - mapTopOffset - (pinY * targetScale);

    final endMatrix = Matrix4.identity()
      // ignore: deprecated_member_use
      ..translate(translateX, translateY, 0.0)
      // ignore: deprecated_member_use
      ..scale(targetScale, targetScale, 1.0);

    _animateMatrixTo(endMatrix);
  }

  void _resetZoom() {
    if (_zoomAnimationController?.isAnimating == true) {
      _zoomAnimationController!.stop();
    }
    setState(() {
      _selectedPoi = null;
      _showSidePanel = false;
    });
    _panelAnimationController.reverse();
    _animateMatrixTo(Matrix4.identity());
  }

  void _animateMatrixTo(Matrix4 targetMatrix) {
    final Matrix4 startMatrix = _transformationController.value;
    if (_zoomAnimationController?.isAnimating == true) {
      _zoomAnimationController!.stop();
    }
    _zoomAnimationController?.dispose();

    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _zoomAnimation = Matrix4Tween(
      begin: startMatrix,
      end: targetMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomAnimationController!,
      curve: Curves.fastOutSlowIn,
    ));

    _zoomAnimation!.addListener(() {
      if (mounted) {
        // Updating value automatically notifies _transformationController listeners (_onTransformationChanged) once
        _transformationController.value = _zoomAnimation!.value;
      }
    });

    _zoomAnimationController!.forward();
  }

  void _openSidePanel(Size viewportSize, double mapWidth, double mapHeight) {
    setState(() {
      _showSidePanel = true;
    });
    _panelAnimationController.forward();
    if (_selectedPoi != null) {
      _zoomToPoi(_selectedPoi!, viewportSize, mapWidth, mapHeight);
    }
  }

  void _closeSidePanel(Size viewportSize, double mapWidth, double mapHeight) {
    _panelAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showSidePanel = false;
        });
        if (_selectedPoi != null) {
          _zoomToPoi(_selectedPoi!, viewportSize, mapWidth, mapHeight);
        }
      }
    });
  }

  void _dismissPoi(Size viewportSize, double mapWidth, double mapHeight) {
    _panelAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showSidePanel = false;
          _selectedPoi = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Entire map fits in viewport by default
        const double imageAspectRatio = 675 / 1200;
        double mapWidth = viewportSize.width;
        double mapHeight = mapWidth / imageAspectRatio;

        if (mapHeight > viewportSize.height) {
          mapHeight = viewportSize.height;
          mapWidth = mapHeight * imageAspectRatio;
        }

        // Sort POIs so selected pin is rendered LAST (highest z-index & frontmost touch target)
        final sortedPois = List<MuseumPoi>.from(widget.pois);
        if (_selectedPoi != null) {
          sortedPois.removeWhere((p) => p.id == _selectedPoi!.id);
          sortedPois.add(_selectedPoi!);
        }

        return Stack(
          children: [
            // Center zoomable map canvas
            Center(
              child: SizedBox(
                width: mapWidth,
                height: mapHeight,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1.0,
                  maxScale: 4.0,
                  clipBehavior: Clip.none,
                  boundaryMargin: const EdgeInsets.all(1200),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Base Map Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/museum_map.jpg',
                          width: mapWidth,
                          height: mapHeight,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildFallbackMap(mapWidth, mapHeight);
                          },
                        ),
                      ),

                      // Hotspot Pins on Map (sorted so active pin stays on top)
                      ...sortedPois.map((poi) {
                        final isSelected = _selectedPoi?.id == poi.id;
                        final pinX = poi.dx * mapWidth;
                        final pinY = poi.dy * mapHeight;

                        return Positioned(
                          left: pinX - 30,
                          top: pinY - 50,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _selectPoi(poi, viewportSize, mapWidth, mapHeight),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: _buildPinMarker(poi, isSelected, viewportSize),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // Top Horizontal Places Chips Row (Google Maps Style)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildTopPlacesChipsBar(viewportSize, mapWidth, mapHeight),
            ),

            // Unclipped Spacious Responsive Info Window Callout attached to screen position of selected pin
            if (_selectedPoi != null && !_showSidePanel)
              _buildResponsiveOverlayInfoWindow(_selectedPoi!, viewportSize, mapWidth, mapHeight),

            // Zoom Floating Action Buttons
            Positioned(
              right: 14,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'zoom_reset',
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.tealAccent,
                    onPressed: _resetZoom,
                    tooltip: 'Reset Map View',
                    child: const Icon(Icons.center_focus_strong_rounded, size: 20),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom_in',
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    onPressed: () {
                      final currentScale = _transformationController.value.getMaxScaleOnAxis();
                      // ignore: deprecated_member_use
                      final endMatrix = _transformationController.value.clone()..scale(1.4, 1.4, 1.0);
                      if (currentScale < 3.8) _animateMatrixTo(endMatrix);
                    },
                    tooltip: 'Zoom In',
                    child: const Icon(Icons.add, size: 20),
                  ),
                ],
              ),
            ),

            // Responsive Right-Side Column / Drawer (Google Maps Style)
            SlideTransition(
              position: _panelSlideAnimation,
              child: _selectedPoi != null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: viewportSize.width > 600 ? 380 : viewportSize.width * 0.88,
                        height: double.infinity,
                        color: const Color(0xFF0F172A),
                        child: _buildRightSideDetailColumn(_selectedPoi!, viewportSize, mapWidth, mapHeight),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  // Horizontal Quick Places Selector Bar at Top
  Widget _buildTopPlacesChipsBar(Size viewportSize, double mapWidth, double mapHeight) {
    final bool isTablet = viewportSize.width >= 600;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: isTablet ? 8 : 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // "View All" Reset Chip
            ActionChip(
              avatar: Icon(
                Icons.explore_rounded,
                size: isTablet ? 18 : 16,
                color: _selectedPoi == null ? Colors.tealAccent : Colors.white70,
              ),
              label: Text(
                'All Places',
                style: TextStyle(
                  fontSize: isTablet ? 13.5 : 12,
                  fontWeight: FontWeight.bold,
                  color: _selectedPoi == null ? Colors.tealAccent : Colors.white,
                ),
              ),
              backgroundColor:
                  _selectedPoi == null ? Colors.teal.withValues(alpha: 0.3) : const Color(0xFF1E293B),
              side: BorderSide(
                color: _selectedPoi == null ? Colors.teal : const Color(0xFF334155),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onPressed: _resetZoom,
            ),
            const SizedBox(width: 8),

            // Places Chips
            ...widget.pois.map((poi) {
              final isSelected = _selectedPoi?.id == poi.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  avatar: Icon(
                    poi.icon,
                    size: isTablet ? 18 : 16,
                    color: isSelected ? Colors.white : poi.color,
                  ),
                  label: Text(
                    poi.tag,
                    style: TextStyle(
                      fontSize: isTablet ? 13.5 : 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  backgroundColor:
                      isSelected ? poi.color : const Color(0xFF1E293B),
                  side: BorderSide(
                    color: isSelected ? Colors.white : poi.color.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onPressed: () => _selectPoi(poi, viewportSize, mapWidth, mapHeight),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // Unclipped Spacious Responsive Info Window Callout attached to screen position of selected pin
  Widget _buildResponsiveOverlayInfoWindow(
    MuseumPoi poi,
    Size viewportSize,
    double mapWidth,
    double mapHeight,
  ) {
    final Matrix4 matrix = _transformationController.value;
    final double scale = matrix.getMaxScaleOnAxis();
    final double tx = matrix.storage[12];
    final double ty = matrix.storage[13];

    // Static offset of SizedBox(mapWidth, mapHeight) inside Center
    final double mapLeftOffset = (viewportSize.width - mapWidth) / 2;
    final double mapTopOffset = (viewportSize.height - mapHeight) / 2;

    final double pinX = poi.dx * mapWidth;
    final double pinY = poi.dy * mapHeight;

    // Precise screen coordinates of the selected pin tip on top-level Stack
    final double screenPinX = mapLeftOffset + (pinX * scale) + tx;
    final double screenPinY = mapTopOffset + (pinY * scale) + ty;

    // Responsive Breakpoint Sizing (Enlarged Card Dimensions & Readable Typography)
    final bool isSmallPhone = viewportSize.width < 420;
    final bool isTablet = viewportSize.width >= 600;

    // Significantly Enlarged Card Width & Constraints
    final double cardWidth = isTablet
        ? math.min(viewportSize.width * 0.55, 430.0)
        : (isSmallPhone ? math.min(viewportSize.width * 0.90, 320.0) : math.min(viewportSize.width * 0.88, 350.0));

    final double maxCardHeight = isTablet ? viewportSize.height * 0.52 : viewportSize.height * 0.44;

    // Prominent pointer arrow dimensions
    final double arrowWidth = isTablet ? 26.0 : 22.0;
    final double arrowHeight = isTablet ? 15.0 : 13.0;

    // Horizontally center card over screenPinX, clamped safely inside screen edges
    double left = screenPinX - (cardWidth / 2);
    if (left < 14) left = 14;
    if (left + cardWidth > viewportSize.width - 14) {
      left = viewportSize.width - cardWidth - 14;
    }

    // Determine vertical placement: place card above pin tip if space allows
    final double pinTopY = screenPinY - (isTablet ? 54.0 : 44.0);
    bool placeAbove = pinTopY > (maxCardHeight + 70);

    // Pointer arrow offset relative to card left edge so callout arrow points EXACTLY to pin tip
    double arrowLeftOffset = (screenPinX - left - (arrowWidth / 2)).clamp(18.0, cardWidth - 36.0);

    return Positioned(
      left: left,
      top: placeAbove ? null : (screenPinY + 10.0),
      bottom: placeAbove ? (viewportSize.height - pinTopY + 2.0) : null,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: cardWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!placeAbove)
                Padding(
                  padding: EdgeInsets.only(left: arrowLeftOffset),
                  child: CustomPaint(
                    size: Size(arrowWidth, arrowHeight),
                    painter: _InvertedTrianglePainter(color: poi.color),
                  ),
                ),

              // Main Info Window Card with Spacious Layout
              Container(
                constraints: BoxConstraints(maxHeight: maxCardHeight),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(isTablet ? 22 : 18),
                  border: Border.all(color: poi.color, width: 2.2),
                  boxShadow: [
                    BoxShadow(
                      color: poi.color.withValues(alpha: 0.45),
                      blurRadius: isTablet ? 24 : 20,
                      spreadRadius: 2,
                    ),
                    const BoxShadow(
                      color: Colors.black54,
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    )
                  ],
                ),
                padding: EdgeInsets.all(isTablet ? 20.0 : (isSmallPhone ? 12.0 : 16.0)),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Category tag, Icon & Close
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isTablet ? 12 : 9,
                              vertical: isTablet ? 5 : 4,
                            ),
                            decoration: BoxDecoration(
                              color: poi.color.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(poi.icon, size: isTablet ? 16 : 13, color: poi.color),
                                const SizedBox(width: 5),
                                Text(
                                  poi.category.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: isTablet ? 12 : (isSmallPhone ? 10 : 11),
                                    fontWeight: FontWeight.bold,
                                    color: poi.color,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _dismissPoi(viewportSize, mapWidth, mapHeight),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Color(0xFF0F172A),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close_rounded, size: isTablet ? 22 : 18, color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Title
                      Text(
                        poi.name,
                        style: TextStyle(
                          fontSize: isTablet ? 20.0 : (isSmallPhone ? 15 : 17),
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),

                      // Short Description
                      Text(
                        poi.shortDescription,
                        style: TextStyle(
                          fontSize: isTablet ? 14.5 : (isSmallPhone ? 11.5 : 13),
                          color: Colors.white70,
                          height: 1.42,
                        ),
                        maxLines: isTablet ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 14),

                      // Rating & Read More Action Button
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(Icons.star_rounded, color: Colors.amber, size: isTablet ? 20 : 16),
                                const SizedBox(width: 4),
                                Text(
                                  '${poi.rating}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: isTablet ? 15 : (isSmallPhone ? 12 : 13),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    '• ${poi.zone}',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: isTablet ? 12 : 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: poi.color,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 18 : (isSmallPhone ? 12 : 16),
                                  vertical: isTablet ? 10 : (isSmallPhone ? 6 : 8),
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
                                ),
                              ),
                              onPressed: () => _openSidePanel(viewportSize, mapWidth, mapHeight),
                              label: Icon(Icons.arrow_forward_rounded, size: isTablet ? 16 : 14),
                              icon: Text(
                                'Read More',
                                style: TextStyle(
                                  fontSize: isTablet ? 13.0 : (isSmallPhone ? 11 : 12),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (placeAbove)
                Padding(
                  padding: EdgeInsets.only(left: arrowLeftOffset),
                  child: CustomPaint(
                    size: Size(arrowWidth, arrowHeight),
                    painter: _TrianglePainter(color: poi.color),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinMarker(MuseumPoi poi, bool isSelected, Size viewportSize) {
    final bool isTablet = viewportSize.width >= 600;

    return AnimatedScale(
      scale: isSelected ? 1.35 : 1.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 12 : 10,
              vertical: isTablet ? 6 : 5,
            ),
            decoration: BoxDecoration(
              color: isSelected ? poi.color : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(isTablet ? 16 : 14),
              border: Border.all(
                color: isSelected ? Colors.white : poi.color,
                width: isSelected ? 2.2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? poi.color : Colors.black).withValues(alpha: isSelected ? 0.65 : 0.4),
                  blurRadius: isSelected ? 16 : 6,
                  spreadRadius: isSelected ? 3 : 0,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  poi.icon,
                  size: isTablet ? 16 : 14,
                  color: isSelected ? Colors.white : poi.color,
                ),
                const SizedBox(width: 5),
                Text(
                  poi.tag,
                  style: TextStyle(
                    fontSize: isTablet ? 11.5 : 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: Size(isTablet ? 14 : 12, isTablet ? 9 : 8),
            painter: _TrianglePainter(
              color: isSelected ? poi.color : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSideDetailColumn(
    MuseumPoi poi,
    Size viewportSize,
    double mapWidth,
    double mapHeight,
  ) {
    final bool isSmallPhone = viewportSize.width < 400;
    final bool isTablet = viewportSize.width >= 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Close Button
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 20 : 14,
                vertical: isTablet ? 14 : 10,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(isTablet ? 8 : 6),
                    decoration: BoxDecoration(
                      color: poi.color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(poi.icon, size: isTablet ? 22 : 18, color: poi.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      poi.name,
                      style: TextStyle(
                        fontSize: isTablet ? 17 : (isSmallPhone ? 13 : 15),
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _closeSidePanel(viewportSize, mapWidth, mapHeight),
                    icon: Icon(Icons.close_rounded, size: isTablet ? 24 : 20, color: Colors.white),
                    tooltip: 'Close details',
                  ),
                ],
              ),
            ),

            // Detailed Content Scrollable Column
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isTablet ? 24 : (isSmallPhone ? 14 : 18)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Banner Card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isTablet ? 22 : (isSmallPhone ? 14 : 18)),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            poi.color.withValues(alpha: 0.35),
                            const Color(0xFF1E293B),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
                        border: Border.all(color: poi.color.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: poi.color,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  poi.category,
                                  style: TextStyle(
                                    fontSize: isTablet ? 12 : (isSmallPhone ? 10 : 11),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.star_rounded, color: Colors.amber, size: isTablet ? 20 : 16),
                              const SizedBox(width: 4),
                              Text(
                                '${poi.rating}',
                                style: TextStyle(
                                  fontSize: isTablet ? 15 : (isSmallPhone ? 12 : 14),
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            poi.name,
                            style: TextStyle(
                              fontSize: isTablet ? 22 : (isSmallPhone ? 16 : 19),
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.location_on_rounded, size: isTablet ? 16 : 13, color: Colors.white60),
                              const SizedBox(width: 4),
                              Text(
                                poi.zone,
                                style: TextStyle(
                                  fontSize: isTablet ? 13 : (isSmallPhone ? 11 : 12),
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Hours & Quick Info
                    Container(
                      padding: EdgeInsets.all(isTablet ? 16 : 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.access_time_filled_rounded, color: Colors.tealAccent, size: isTablet ? 22 : 18),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Operating Hours',
                                  style: TextStyle(fontSize: isTablet ? 11.5 : 10, color: Colors.white38),
                                ),
                                Text(
                                  poi.openHours,
                                  style: TextStyle(
                                    fontSize: isTablet ? 14.5 : (isSmallPhone ? 11.5 : 13),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Detailed Description Header
                    Text(
                      'Overview',
                      style: TextStyle(
                        fontSize: isTablet ? 17 : 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      poi.fullDescription,
                      style: TextStyle(
                        fontSize: isTablet ? 14.5 : (isSmallPhone ? 12 : 13.5),
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Key Highlights List
                    Text(
                      'Key Highlights',
                      style: TextStyle(
                        fontSize: isTablet ? 17 : 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...poi.highlights.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: isTablet ? 18 : 16, color: poi.color),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: TextStyle(
                                  fontSize: isTablet ? 14 : (isSmallPhone ? 11.5 : 12.5),
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Action Buttons Row (Google Maps style)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: poi.color,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: isTablet ? 14 : 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Navigating to ${poi.name}...'),
                                  backgroundColor: const Color(0xFF1E293B),
                                ),
                              );
                            },
                            icon: Icon(Icons.directions_rounded, size: isTablet ? 20 : 16),
                            label: Text(
                              'Directions',
                              style: TextStyle(fontSize: isTablet ? 14 : (isSmallPhone ? 11 : 13), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.tealAccent,
                            side: const BorderSide(color: Colors.teal),
                            padding: EdgeInsets.symmetric(
                              vertical: isTablet ? 14 : 10,
                              horizontal: isTablet ? 18 : 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Saved ${poi.name} to favorites!'),
                                backgroundColor: const Color(0xFF1E293B),
                              ),
                            );
                          },
                          child: Icon(Icons.bookmark_add_rounded, size: isTablet ? 22 : 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackMap(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF1E293B),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.map_rounded, size: 64, color: Colors.teal),
            SizedBox(height: 12),
            Text(
              'Museum Floor Map',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => oldDelegate.color != color;
}

class _InvertedTrianglePainter extends CustomPainter {
  final Color color;

  _InvertedTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _InvertedTrianglePainter oldDelegate) => oldDelegate.color != color;
}
