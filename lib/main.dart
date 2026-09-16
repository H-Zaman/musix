import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:provider/provider.dart';
import 'package:musix/providers/playback_provider.dart';
import 'package:musix/services/musix_audio_handler.dart';
import 'package:musix/musix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:musix/providers/youtube_downloader_provider.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint('=== App Starting ===');

    final prefs = await SharedPreferences.getInstance();
    debugPrint('=== SharedPreferences Initialized ===');

    try {
      await SoLoud.instance.init();
      debugPrint('=== SoLoud Initialized ===');
    } catch (e) {
      debugPrint('=== SoLoud Init Error: $e ===');
    }

    final playbackProvider = PlaybackProvider(prefs);

    try {
      await AudioService.init(
        builder: () => MusixAudioHandler(playbackProvider),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.shuvro.musix',
          androidNotificationChannelName: 'Musix Playback',
          androidNotificationOngoing: true,
        ),
      );
      debugPrint('=== AudioService Initialized ===');
    } catch (e) {
      debugPrint('=== AudioService Init Error: $e ===');
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: playbackProvider),
          ChangeNotifierProvider(create: (_) => YoutubeDownloaderProvider(playbackProvider)),
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
