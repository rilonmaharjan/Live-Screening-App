import 'package:flutter/material.dart';

class MuseumPoi {
  final String id;
  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final String shortDescription;
  final String fullDescription;
  final double dx; // Normalized X coordinate on map (0.0 to 1.0)
  final double dy; // Normalized Y coordinate on map (0.0 to 1.0)
  final double rating;
  final String openHours;
  final String zone;
  final List<String> highlights;
  final String tag;

  const MuseumPoi({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    required this.shortDescription,
    required this.fullDescription,
    required this.dx,
    required this.dy,
    required this.rating,
    required this.openHours,
    required this.zone,
    required this.highlights,
    required this.tag,
  });

  static List<MuseumPoi> get samplePois => [
        MuseumPoi(
          id: 'hospital',
          name: 'Medical & First Aid Center',
          category: 'Health & Safety',
          icon: Icons.local_hospital_rounded,
          color: const Color(0xFFEF4444),
          shortDescription:
              'Fully equipped 24/7 medical station with certified emergency medical personnel.',
          fullDescription:
              'The Museum First Aid Center provides emergency medical care, quiet rest rooms, health monitoring, and immediate basic care. Qualified nursing staff are present during all operating hours.',
          dx: 0.28,
          dy: 0.24,
          rating: 4.9,
          openHours: '9:00 AM - 6:00 PM Daily',
          zone: 'West Wing - Level 1',
          highlights: [
            '24/7 Paramedic Staff',
            'Wheelchair & Stretcher Ready',
            'AED & Basic Care Kits',
            'Quiet Rest Area'
          ],
          tag: 'HOSPITAL',
        ),
        MuseumPoi(
          id: 'zoo',
          name: 'Prehistoric Wildlife Zoo',
          category: 'Live Animals',
          icon: Icons.pets_rounded,
          color: const Color(0xFF10B981),
          shortDescription:
              'Interactive sanctuary featuring live reptiles, avian species, and ancient flora.',
          fullDescription:
              'Walk through living biomes modeled after Cretaceous-era rainforests. Observe rare living fossils, giant tortoises, and exotic birds up close in an immersive climate-controlled sanctuary.',
          dx: 0.72,
          dy: 0.35,
          rating: 4.8,
          openHours: '9:30 AM - 5:30 PM',
          zone: 'Bio-Dome Annex',
          highlights: [
            'Interactive Touch Pools',
            'Guided Feeding Tours',
            'Tropical Rainforest Canopy',
            'Live Herpetology Lab'
          ],
          tag: 'ZOO',
        ),
        MuseumPoi(
          id: 'dino',
          name: 'T-Rex & Fossil Gallery',
          category: 'Paleontology',
          icon: Icons.coronavirus_rounded,
          color: const Color(0xFFF59E0B),
          shortDescription:
              'Home to "Apex" – the 40-foot real Tyrannosaurus Rex skeleton exhibit.',
          fullDescription:
              'Explore 65 million years of Earth history. Features complete fossil skeletons of T-Rex, Triceratops, and Velociraptors, alongside real fossil excavation touch stations.',
          dx: 0.45,
          dy: 0.62,
          rating: 5.0,
          openHours: '9:00 AM - 6:00 PM',
          zone: 'Central Atrium',
          highlights: [
            'Full T-Rex Skeleton',
            'Real Fossil Touch Lab',
            '3D Dino Motion Cinema',
            'VR Excavation Sim'
          ],
          tag: 'PALEONTOLOGY',
        ),
        MuseumPoi(
          id: 'cafe',
          name: 'Jurassic Bistro & Cafe',
          category: 'Dining',
          icon: Icons.restaurant_rounded,
          color: const Color(0xFF8B5CF6),
          shortDescription:
              'Gourmet dining featuring thematic meals, fresh coffee, and panoramic garden views.',
          fullDescription:
              'Relax and refuel with artisan coffees, stone-baked pizzas, organic salads, and dinosaur-themed treats for kids. Indoor and outdoor patio seating available.',
          dx: 0.18,
          dy: 0.75,
          rating: 4.7,
          openHours: '8:30 AM - 5:00 PM',
          zone: 'Garden Terrace',
          highlights: [
            'Artisan Coffee Bar',
            'Kid-Friendly Dino Meals',
            'Outdoor Botanical Terrace',
            'Gluten-Free Options'
          ],
          tag: 'DINING',
        ),
      ];
}
