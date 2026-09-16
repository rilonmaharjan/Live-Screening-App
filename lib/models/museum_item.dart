import 'package:flutter/material.dart';

class MuseumItem {
  final String id;
  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final String shortDescription;
  final String fullDescription;
  final double rating;
  final int reviewCount;
  final String openingHours;
  final String floorLevel;
  final List<String> highlights;
  final List<Map<String, String>> reviews;
  final double dx; // Normalized 0.0 - 1.0 X position on map
  final double dy; // Normalized 0.0 - 1.0 Y position on map
  final String imagePath;

  const MuseumItem({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    required this.shortDescription,
    required this.fullDescription,
    required this.rating,
    required this.reviewCount,
    required this.openingHours,
    required this.floorLevel,
    required this.highlights,
    required this.reviews,
    required this.dx,
    required this.dy,
    required this.imagePath,
  });

  static final List<MuseumItem> sampleItems = [
    const MuseumItem(
      id: 'hospital',
      name: 'Medical & First Aid Pavilion',
      category: 'Emergency & Wellness',
      icon: Icons.local_hospital_rounded,
      color: Color(0xFFEF5350),
      shortDescription: '24/7 First Aid station equipped with medical staff, AEDs, and emergency care.',
      fullDescription:
          'The Medical & First Aid Pavilion provides immediate health support for all museum guests. Equipped with certified paramedics, quiet rest cubicles, rehydration stations, pediatric care facilities, and direct emergency response links. Complimentary medical checkups, wheelchair rentals, and sensory rest areas are available here.',
      rating: 4.9,
      reviewCount: 328,
      openingHours: 'Open 24/7 during Museum Operating Hours',
      floorLevel: 'Ground Floor - Zone A1',
      highlights: [
        'Certified Paramedics on Duty',
        'AED Defibrillators & Emergency Response',
        'Quiet Rest & Sensory Recharge Rooms',
        'Free Wheelchair & Stroller Rental'
      ],
      reviews: [
        {
          'user': 'Dr. Sarah Connor',
          'rating': '5.0',
          'comment': 'Exceptionally clean and helpful staff when my son felt dizzy. Fast care!'
        },
        {
          'user': 'Mark R.',
          'rating': '5.0',
          'comment': 'Equipped with quiet rooms for kids needing a break. Wonderful facility.'
        }
      ],
      dx: 0.22,
      dy: 0.28,
      imagePath: 'assets/images/museum_map.png',
    ),
    const MuseumItem(
      id: 'zoo',
      name: 'Living Bio-Dome Zoo',
      category: 'Wildlife & Nature',
      icon: Icons.pets_rounded,
      color: Color(0xFF66BB6A),
      shortDescription: 'Interactive rainforest habitat housing rare exotic fauna and butterfly gardens.',
      fullDescription:
          'Step into a climate-controlled tropical rainforest ecosystem containing over 150 species of birds, reptiles, and nocturnal mammals. Features an overhead glass skywalk, live feeding demonstrations, butterfly sanctuary, and interactive touch tanks with marine species under guide supervision.',
      rating: 4.8,
      reviewCount: 1420,
      openingHours: '9:00 AM – 6:00 PM',
      floorLevel: 'East Wing - Level 1',
      highlights: [
        'Overhead Canopy Glass Walkway',
        'Tropical Butterfly Sanctuary',
        'Daily Live Feeding Presentations (11 AM & 3 PM)',
        'Kid-Friendly Marine Touch Tank'
      ],
      reviews: [
        {
          'user': 'Elena Rostova',
          'rating': '5.0',
          'comment': 'The glass skywalk over the rainforest canopy is breathtaking!'
        },
        {
          'user': 'David Chen',
          'rating': '4.5',
          'comment': 'My kids loved seeing the butterflies land right on their hands.'
        }
      ],
      dx: 0.72,
      dy: 0.26,
      imagePath: 'assets/images/museum_map.png',
    ),
    const MuseumItem(
      id: 'dino',
      name: 'Prehistoric Dinosaur Fossil Hall',
      category: 'Paleontology & Geology',
      icon: Icons.adb_rounded,
      color: Color(0xFFFFA726),
      shortDescription: 'Full-scale Tyrannosaurus Rex skeleton & immersive Jurassic dig zone for kids.',
      fullDescription:
          'Walk beneath towering prehistoric giants! Featuring the iconic 40-foot T-Rex fossil cast "Titan", real triceratops skull specimens, amber-encased ancient insects, and an augmented reality dig zone where visitors uncover virtual fossils in real time.',
      rating: 4.9,
      reviewCount: 2150,
      openingHours: '9:00 AM – 7:00 PM',
      floorLevel: 'Central Atrium - Grand Hall',
      highlights: [
        '40ft Full T-Rex & Brachiosaurus Skeletons',
        'Interactive AR Dig Experience',
        'Prehistoric Amber Touch Exhibits',
        'Geological Meteorite Display'
      ],
      reviews: [
        {
          'user': 'Alex Vance',
          'rating': '5.0',
          'comment': 'The scale of the T-Rex skeleton takes your breath away. Must see!'
        },
        {
          'user': 'Priya Patel',
          'rating': '5.0',
          'comment': 'AR dig zone was the highlight for the whole family.'
        }
      ],
      dx: 0.50,
      dy: 0.45,
      imagePath: 'assets/images/museum_map.png',
    ),
    const MuseumItem(
      id: 'science',
      name: 'Future Tech & Robotics Lab',
      category: 'Science & AI Innovation',
      icon: Icons.precision_manufacturing_rounded,
      color: Color(0xFF42A5F5),
      shortDescription: 'Hands-on robotics lab, quantum physics demos, and AI humanoids.',
      fullDescription:
          'Experience the frontier of human innovation! Interact with autonomous humanoid robots, test magnetic levitation trains, program basic AI arms, and explore immersive hologram theaters showing space exploration missions.',
      rating: 4.7,
      reviewCount: 980,
      openingHours: '9:30 AM – 6:30 PM',
      floorLevel: 'West Wing - Level 2',
      highlights: [
        'Interactive Humanoid Robot Conversations',
        'MagLev Train Track Demonstration',
        'Quantum Computing Simulator',
        '3D Holographic Theater'
      ],
      reviews: [
        {
          'user': 'Jason Miller',
          'rating': '5.0',
          'comment': 'Super interactive! The robots respond live and play chess.'
        }
      ],
      dx: 0.25,
      dy: 0.65,
      imagePath: 'assets/images/museum_map.png',
    ),
    const MuseumItem(
      id: 'art',
      name: 'Classical Art & Heritage Pavilion',
      category: 'Fine Arts & History',
      icon: Icons.palette_rounded,
      color: Color(0xFFAB47BC),
      shortDescription: 'Renaissance masterworks, ancient sculptures, and digital immersion gallery.',
      fullDescription:
          'Housing pristine masterworks from the 15th through 19th centuries, marble Greek sculptures, and an ultra-high definition projection dome offering 360-degree digital walkthroughs of historical world wonders.',
      rating: 4.8,
      reviewCount: 860,
      openingHours: '10:00 AM – 6:00 PM',
      floorLevel: 'North Gallery - Level 2',
      highlights: [
        'Master Oil Painting Collection',
        'Ancient Greek & Roman Marble Statues',
        '360° Immersive Projection Dome',
        'Audio Guide in 12 Languages'
      ],
      reviews: [
        {
          'user': 'Claire Dubois',
          'rating': '5.0',
          'comment': 'The projection dome made art history feel so vivid and alive!'
        }
      ],
      dx: 0.78,
      dy: 0.68,
      imagePath: 'assets/images/museum_map.png',
    ),
    const MuseumItem(
      id: 'cafe',
      name: 'Atrium Cafe & Souvenir Shop',
      category: 'Dining & Retail',
      icon: Icons.restaurant_rounded,
      color: Color(0xFF26A69A),
      shortDescription: 'Artisanal espresso, organic meals, and exclusive museum memorabilia.',
      fullDescription:
          'Relax and refuel in our glass-roof garden lounge. Serving organic farm-to-table cuisine, artisanal pastries, specialty coffee, and features a souvenir gift store stocked with replica fossils, science kits, and art prints.',
      rating: 4.6,
      reviewCount: 650,
      openingHours: '8:30 AM – 7:30 PM',
      floorLevel: 'Ground Floor - Main Entrance',
      highlights: [
        'Farm-to-Table Organic Menu',
        'Specialty Cold Brews & Pastries',
        'Museum Souvenirs & Educational Toys',
        'Indoor Garden Seating with Wi-Fi'
      ],
      reviews: [
        {
          'user': 'Tom Hanks',
          'rating': '4.5',
          'comment': 'Great coffee and delicious pastries after walking around all day.'
        }
      ],
      dx: 0.50,
      dy: 0.85,
      imagePath: 'assets/images/museum_map.png',
    ),
  ];
}
