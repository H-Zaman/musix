import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:musix/providers/playback_provider.dart';
import 'package:musix/musix.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('=== App Starting ===');

    final prefs = await SharedPreferences.getInstance();
    debugPrint('=== SharedPreferences Initialized ===');

    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.shuvro.musix',
        androidNotificationChannelName: 'Musix Playback',
        androidNotificationOngoing: true,
      );
      debugPrint('=== JustAudioBackground Initialized ===');
    } catch (e) {
      debugPrint('=== JustAudioBackground Error: $e ===');
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => PlaybackProvider(prefs)),
        ],
        child: const MusixApp(),
      ),
    );
    debugPrint('=== runApp Executed ===');
  }, (error, stack) {
    debugPrint('=== CRITICAL CRASH ===');
    debugPrint(error.toString());
    debugPrint(stack.toString());
  });
}
