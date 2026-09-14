import 'package:flutter/material.dart';
import 'package:musix/screens/musix_player_screen.dart';
import 'package:musix/theme/winamp_theme.dart';

class MusixApp extends StatelessWidget {
  const MusixApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Musix',
      debugShowCheckedModeBanner: false,
      theme: WinampTheme.darkTheme,
      home: const MusixPlayerScreen(),
    );
  }
}

