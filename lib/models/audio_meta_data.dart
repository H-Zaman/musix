import 'package:audio_service/audio_service.dart';

class AudioMetadata {
  final String title;
  final String artist;
  final String album;
  final String filePath;
  final String? artworkUri;

  AudioMetadata({
    required this.title,
    required this.artist,
    required this.album,
    required this.filePath,
    this.artworkUri,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'album': album,
    'filePath': filePath,
    'artworkUri': artworkUri,
  };

  factory AudioMetadata.fromJson(Map<String, dynamic> json) => AudioMetadata(
    title: json['title'],
    artist: json['artist'],
    album: json['album'],
    filePath: json['filePath'],
    artworkUri: json['artworkUri'],
  );

  MediaItem toMediaItem({Duration? duration}) {
    return MediaItem(
      id: filePath,
      album: album,
      title: title,
      artist: artist,
      duration: duration,
      artUri: artworkUri != null ? Uri.parse(artworkUri!) : null,
      extras: {'url': filePath},
    );
  }
}
