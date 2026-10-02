import 'package:flutter_test/flutter_test.dart';
import 'package:rndscreeningap/models/museum_item.dart';
import 'package:rndscreeningap/widgets/museum_poi.dart';

void main() {
  group('MuseumItem.sampleItems', () {
    final items = MuseumItem.sampleItems;

    test('is not empty and ids are unique', () {
      expect(items, isNotEmpty);
      expect(items.map((e) => e.id).toSet().length, items.length);
    });

    test('every item has complete, sane data', () {
      for (final item in items) {
        expect(item.name, isNotEmpty, reason: item.id);
        expect(item.category, isNotEmpty, reason: item.id);
        expect(item.shortDescription, isNotEmpty, reason: item.id);
        expect(item.fullDescription, isNotEmpty, reason: item.id);
        expect(item.highlights, isNotEmpty, reason: item.id);
        expect(item.imagePath, isNotEmpty, reason: item.id);
        expect(item.rating, inInclusiveRange(0.0, 5.0), reason: item.id);
        expect(item.reviewCount, greaterThanOrEqualTo(0), reason: item.id);
        expect(item.dx, inInclusiveRange(0.0, 1.0), reason: item.id);
        expect(item.dy, inInclusiveRange(0.0, 1.0), reason: item.id);
      }
    });

    test('every review has user, rating and comment', () {
      for (final item in items) {
        for (final review in item.reviews) {
          expect(review.keys, containsAll(['user', 'rating', 'comment']),
              reason: item.id);
          expect(double.tryParse(review['rating']!), isNotNull,
              reason: '${item.id} has a non-numeric review rating');
        }
      }
    });
  });

  group('MuseumPoi.samplePois', () {
    final pois = MuseumPoi.samplePois;

    test('is not empty and ids/tags are unique', () {
      expect(pois, isNotEmpty);
      expect(pois.map((e) => e.id).toSet().length, pois.length);
      expect(pois.map((e) => e.tag).toSet().length, pois.length);
    });

    test('coordinates are normalized and ratings are valid', () {
      for (final poi in pois) {
        expect(poi.dx, inInclusiveRange(0.0, 1.0), reason: poi.id);
        expect(poi.dy, inInclusiveRange(0.0, 1.0), reason: poi.id);
        expect(poi.rating, inInclusiveRange(0.0, 5.0), reason: poi.id);
        expect(poi.name, isNotEmpty, reason: poi.id);
        expect(poi.highlights, isNotEmpty, reason: poi.id);
      }
    });
  });
}
