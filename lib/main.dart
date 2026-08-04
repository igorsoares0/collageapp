import 'dart:async';

import 'package:flutter/material.dart';

import 'src/api/entitlements.dart';
import 'src/screens/gallery_screen.dart';
import 'src/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final entitlements = EntitlementsService();
  // Fire-and-forget: the gallery renders immediately and the locks resolve
  // as soon as RevenueCat answers (or stay on when it can't).
  unawaited(entitlements.init());
  runApp(LayerApp(entitlements: entitlements));
}

class LayerApp extends StatelessWidget {
  final EntitlementsService entitlements;

  const LayerApp({super.key, required this.entitlements});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Layer',
      theme: buildAppTheme(),
      home: GalleryScreen(entitlements: entitlements),
    );
  }
}
