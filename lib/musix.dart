import 'package:flutter/material.dart';
import 'package:musix/screens/musix_player_screen.dart';
import 'package:musix/screens/youtube_downloader_screen.dart';
import 'package:musix/theme/winamp_theme.dart';

class MusixApp extends StatelessWidget {
  const MusixApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static const String _downloaderRoute = '/downloader';

  /// Opens the downloader unless it is already the top screen, so repeated
  /// share intents don't stack copies.
  static void openDownloader() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    var alreadyOpen = false;
    navigator.popUntil((route) {
      alreadyOpen = route.settings.name == _downloaderRoute;
      return true; // inspect the top route only, never pop
    });
    if (alreadyOpen) return;
    navigator.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: _downloaderRoute),
        builder: (_) => const YoutubeDownloaderScreen(),
      ),
    );
  }

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
