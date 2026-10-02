import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/widgets/museum_map_view.dart';
import 'package:rndscreeningap/widgets/museum_poi.dart';

import '../helpers/fakes.dart';

final _pois = MuseumPoi.samplePois;

Future<void> _pump(WidgetTester tester, {Size size = const Size(400, 800)}) async {
  usePhoneSurface(tester, size: size);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: MuseumMapView(pois: _pois)),
  ));
  await tester.pump();
}

Finder _chip(String label) => find.widgetWithText(ActionChip, label);

/// The chip bar scrolls horizontally on phone widths, so bring the chip into
/// view before tapping it.
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.ensureVisible(_chip(label));
  await tester.pump();
  await tester.tap(_chip(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The detail panel is always in the tree while a POI is selected and is just
/// slid off-screen when closed, so "open" means "inside the viewport".
bool _panelOnScreen(WidgetTester tester, double viewportWidth) =>
    tester.getTopLeft(find.text('Overview')).dx < viewportWidth;

double _scale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

/// Invokes "Read More" directly: the callout floats at the pin's screen
/// position and may sit partly outside the test surface.
Future<void> _openDetails(WidgetTester tester) async {
  final button = tester.widget<ButtonStyleButton>(find.ancestor(
    of: find.text('Read More'),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  ));
  button.onPressed!();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('renders the map, the "All Places" chip and one chip per POI',
      (tester) async {
    await _pump(tester);

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(_chip('All Places'), findsOneWidget);
    for (final poi in _pois) {
      expect(_chip(poi.tag), findsOneWidget, reason: poi.tag);
    }
  });

  testWidgets('shows a pin marker for every POI on the map', (tester) async {
    await _pump(tester);

    for (final poi in _pois) {
      // One in the chip bar + one pin on the map.
      expect(find.text(poi.tag), findsNWidgets(2), reason: poi.tag);
    }
  });

  testWidgets('nothing is selected initially', (tester) async {
    await _pump(tester);

    expect(find.text('Read More'), findsNothing);
    expect(find.text('Overview'), findsNothing);
    expect(_scale(tester), 1.0);
  });

  testWidgets('selecting a POI chip zooms in and shows its callout',
      (tester) async {
    await _pump(tester);
    final poi = _pois.first;

    await _tapChip(tester, poi.tag);

    expect(find.text('Read More'), findsOneWidget);
    expect(find.text(poi.shortDescription), findsOneWidget);
    expect(_scale(tester), greaterThan(1.0));
  });

  testWidgets('selecting another POI replaces the callout', (tester) async {
    await _pump(tester);

    await _tapChip(tester, _pois[0].tag);
    expect(find.text(_pois[0].shortDescription), findsOneWidget);

    await _tapChip(tester, _pois[1].tag);

    expect(find.text(_pois[1].shortDescription), findsOneWidget);
    expect(find.text(_pois[0].shortDescription), findsNothing);
  });

  testWidgets('"All Places" clears the selection and resets the zoom',
      (tester) async {
    await _pump(tester);
    await _tapChip(tester, _pois.first.tag);
    expect(find.text('Read More'), findsOneWidget);

    await _tapChip(tester, 'All Places');

    expect(find.text('Read More'), findsNothing);
    expect(_scale(tester), closeTo(1.0, 1e-6));
  });

  testWidgets('"Read More" opens the detail side panel', (tester) async {
    await _pump(tester);
    final poi = _pois.first;
    await _tapChip(tester, poi.tag);
    expect(find.text('Overview'), findsOneWidget);
    expect(_panelOnScreen(tester, 400), isFalse); // built, but slid away

    await _openDetails(tester);

    expect(_panelOnScreen(tester, 400), isTrue);
    expect(find.text('Read More'), findsNothing); // callout swaps for the panel
    expect(find.text('Key Highlights'), findsOneWidget);
    expect(find.text(poi.fullDescription), findsOneWidget);
    expect(find.text(poi.openHours), findsOneWidget);
    for (final highlight in poi.highlights) {
      expect(find.text(highlight), findsOneWidget, reason: highlight);
    }
  });

  testWidgets('the side panel can be closed again', (tester) async {
    await _pump(tester);
    await _tapChip(tester, _pois.first.tag);
    await _openDetails(tester);
    expect(_panelOnScreen(tester, 400), isTrue);

    await tester.tap(find.byTooltip('Close details'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_panelOnScreen(tester, 400), isFalse);
    expect(find.text('Read More'), findsOneWidget); // callout is back
  });

  testWidgets('zoom-in button increases the scale and reset restores it',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byTooltip('Zoom In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_scale(tester), closeTo(1.4, 0.01));

    await tester.tap(find.byTooltip('Reset Map View'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_scale(tester), closeTo(1.0, 1e-6));
  });

  testWidgets('works on a tablet-sized viewport', (tester) async {
    await _pump(tester, size: const Size(900, 1200));

    await _tapChip(tester, _pois[2].tag);

    expect(find.text('Read More'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders with an empty POI list', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: MuseumMapView(pois: [])),
    ));
    await tester.pump();

    expect(_chip('All Places'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
