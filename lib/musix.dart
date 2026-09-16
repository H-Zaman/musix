import 'package:flutter/material.dart';
import 'package:musix/screens/musix_player_screen.dart';
import 'package:musix/theme/winamp_theme.dart';

class MusixApp extends StatelessWidget {
  const MusixApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Musix',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: WinampTheme.darkTheme,
      home: const MusixPlayerScreen(),
    );
  }
}

