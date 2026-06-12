import 'package:flutter/material.dart';

import 'src/screens/gallery_screen.dart';

void main() {
  runApp(const CollageApp());
}

class CollageApp extends StatelessWidget {
  const CollageApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Collage Studio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
      ),
      home: const GalleryScreen(),
    );
  }
}
