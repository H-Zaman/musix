import 'package:audio_service/audio_service.dart';
import 'package:musix/providers/playback_provider.dart';

/// Bridges lock-screen / notification controls to [PlaybackProvider].
/// SoLoud has no built-in media-session support, so this forwards
/// transport commands to the provider and republishes its state.
class MusixAudioHandler extends BaseAudioHandler {
  final PlaybackProvider provider;

  MusixAudioHandler(this.provider) {
    provider.addListener(_broadcastState);
    _broadcastState();
  }

  void _broadcastState() {
    final song = provider.currentSong;
    if (song != null) {
      mediaItem.add(song.toMediaItem(duration: provider.currentDuration));
    }
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        provider.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: AudioProcessingState.ready,
      playing: provider.isPlaying,
      updatePosition: provider.currentPosition,
    ));
  }

  @override
  Future<void> play() => provider.playOrResume();

  @override
  Future<void> pause() async => provider.pause();

  @override
  Future<void> stop() => provider.stop();

  @override
  Future<void> skipToNext() => provider.next();

  @override
  Future<void> skipToPrevious() => provider.previous();

  @override
  Future<void> seek(Duration position) async => provider.seek(position);
}
