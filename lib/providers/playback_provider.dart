import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musix/models/audio_meta_data.dart';
import 'package:musix/models/playlist.dart';
import 'package:musix/models/position.dart';
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart' as pp;

class PlaybackProvider extends ChangeNotifier with WidgetsBindingObserver {
  late AudioPlayer _player;
  final ConcatenatingAudioSource _playlistSource = ConcatenatingAudioSource(children: []);
  
  final List<AudioMetadata> _allSongs = [];
  List<AudioMetadata> _playableSongs = [];
  final List<Playlist> _customPlaylists = [];
  
  bool _isScanning = false;
  final SharedPreferences _prefs;

  static const String _prefSongsKey = 'musix_all_songs';
  static const String _prefCustomPlaylistsKey = 'musix_custom_playlists';
  static const String _prefIndexKey = 'musix_current_index';
  static const String _prefPositionKey = 'musix_position';

  AudioPlayer get player => _player;
  List<AudioMetadata> get allSongs => _allSongs;
  List<Playlist> get customPlaylists => _customPlaylists;
  bool get isScanning => _isScanning;

  Stream<PositionData> get positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) => PositionData(position, bufferedPosition, duration ?? Duration.zero),
      );

  PlaybackProvider(this._prefs) {
    WidgetsBinding.instance.addObserver(this);
    _player = AudioPlayer();
    _initAudioSession();
    _listenToPlayerChanges();
    _loadInitialState();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  void _listenToPlayerChanges() {
    _player.positionStream.listen((position) => _prefs.setInt(_prefPositionKey, position.inMilliseconds));
    _player.currentIndexStream.listen((index) {
      if (index != null) {
        _prefs.setInt(_prefIndexKey, index);
        notifyListeners();
      }
    });
  }

  Future<void> _loadInitialState() async {
    // 1. Load cached songs for instant UI
    final songsJson = _prefs.getString(_prefSongsKey);
    if (songsJson != null) {
      final List<dynamic> decoded = jsonDecode(songsJson);
      _allSongs.addAll(decoded.map((e) => AudioMetadata.fromJson(e)));
      await _updatePlayerSource(_allSongs);
      
      final savedIndex = _prefs.getInt(_prefIndexKey) ?? 0;
      final savedPos = _prefs.getInt(_prefPositionKey) ?? 0;
      final playlistLength = _playlistSource.length;
      if (playlistLength > 0) {
        await _player.seek(Duration(milliseconds: savedPos), index: savedIndex < playlistLength ? savedIndex : 0);
      }
    }

    // 2. Load custom playlists
    final playlistJson = _prefs.getString(_prefCustomPlaylistsKey);
    if (playlistJson != null) {
      final List<dynamic> decoded = jsonDecode(playlistJson);
      _customPlaylists.addAll(decoded.map((e) => Playlist.fromJson(e)));
    }

    notifyListeners();

    // 3. Automatic background scan of the App's Documents folder
    _autoScanLibrary();
  }

  Future<void> _autoScanLibrary() async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      final docsDir = await pp.getApplicationDocumentsDirectory();
      final List<AudioMetadata> foundSongs = [];
      
      // Recursive scan of the app's own directory (full permission granted by iOS)
      final entities = docsDir.listSync(recursive: true, followLinks: false);
      
      for (var entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (['.mp3', '.m4a', '.wav', '.aac', '.flac'].contains(ext)) {
            foundSongs.add(AudioMetadata(
              title: p.basenameWithoutExtension(entity.path),
              artist: 'Local Artist',
              album: p.basename(p.dirname(entity.path)),
              filePath: entity.path,
            ));
          }
        }
      }

      if (foundSongs.length != _allSongs.length || foundSongs.length != _playableSongs.length) {
        _allSongs.clear();
        _allSongs.addAll(foundSongs);
        await _prefs.setString(_prefSongsKey, jsonEncode(_allSongs.map((e) => e.toJson()).toList()));
        if (!_player.playing || _playlistSource.length == 0) {
          await _updatePlayerSource(_allSongs);
        }
      }
    } catch (e) {
      debugPrint('Library scan error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  // Allow manual import from other locations via picker and cleanly handle duplicates
  Future<void> importSongs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, 
      allowMultiple: true,
    );
    if (result != null) {
      final docsDir = await pp.getApplicationDocumentsDirectory();
      for (var file in result.files) {
        if (file.path != null) {
          final newPath = p.join(docsDir.path, file.name);
          // If the file is not already in our internal app container directory, duplicate it inside safely
          if (!file.path!.startsWith(docsDir.path)) {
            final sourceFile = File(file.path!);
            await sourceFile.copy(newPath);
            
            // Clean up original file right after a successful verification copy to prevent system duplicates
            try {
              if (await sourceFile.exists()) {
                await sourceFile.delete();
                debugPrint('Successfully deleted original temporary source file: ${file.path}');
              }
            } catch (e) {
              // On iOS real devices, if the file was selected from a external iCloud container, 
              // the system treats it as read-only temporary context stream, so direct delete is restricted.
              debugPrint('Note: System handled or cloud-synced files do not allow direct app deletion: $e');
            }
          }
        }
      }
      _autoScanLibrary();
    }
  }

  Future<void> _updatePlayerSource(List<AudioMetadata> songs) async {
    await _playlistSource.clear();
    _playableSongs = songs.where((s) => File(s.filePath).existsSync()).toList();
    await _playlistSource.addAll(
      _playableSongs.map((s) => AudioSource.file(s.filePath, tag: s.toMediaItem())).toList(),
    );
    if (_player.audioSource == null) {
      await _player.setAudioSource(_playlistSource);
    }
  }

  Future<void> playTrack(AudioMetadata track) async {
    final index = _playableSongs.indexWhere((s) => s.filePath == track.filePath);
    if (index == -1) return;
    try {
      await _player.seek(Duration.zero, index: index);
      _player.play();
    } on PlatformException catch (e) {
      // The native queue can be mid-rebuild (playlist rescan in progress) when the
      // user taps, so the Dart-side index is momentarily invalid on the native side.
      debugPrint('playTrack seek failed, queue likely mid-rebuild: $e');
    }
  }

  // --- PLAYLIST LOGIC ---

  Future<void> createPlaylist(String name) async {
    final newPlaylist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      trackFilePaths: [],
    );
    _customPlaylists.add(newPlaylist);
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> addSongToPlaylist(Playlist playlist, AudioMetadata song) async {
    if (!playlist.trackFilePaths.contains(song.filePath)) {
      playlist.trackFilePaths.add(song.filePath);
      await _savePlaylists();
      notifyListeners();
    }
  }

  Future<void> _savePlaylists() async {
    await _prefs.setString(_prefCustomPlaylistsKey, jsonEncode(_customPlaylists.map((e) => e.toJson()).toList()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _player.dispose();
    super.dispose();
  }
}
