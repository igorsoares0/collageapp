import 'dart:async';

import 'package:flutter/material.dart';

import 'src/api/entitlements.dart';
import 'src/screens/gallery_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final entitlements = EntitlementsService();
  // Fire-and-forget: the gallery renders immediately and the locks resolve
  // as soon as RevenueCat answers (or stay on when it can't).
  unawaited(entitlements.init());
  runApp(CollageApp(entitlements: entitlements));
}

class CollageApp extends StatelessWidget {
  final EntitlementsService entitlements;

  const CollageApp({super.key, required this.entitlements});

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
      home: GalleryScreen(entitlements: entitlements),
    );
  }
}
