import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart' hide AudioMetadata;
import 'package:musix/models/audio_meta_data.dart';
import 'package:musix/models/position.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart' as pp;

enum RepeatMode { off, all, one }

class PlaybackProvider extends ChangeNotifier {
  final SoLoud _soloud = SoLoud.instance;

  final List<AudioMetadata> _allSongs = [];
  List<AudioMetadata> _playableSongs = [];
  List<AudioMetadata> _filteredSongs = [];
  List<int> _playOrder = [];
  int _orderPos = -1;

  AudioSource? _currentSource;
  SoundHandle? _currentHandle;
  AudioMetadata? _currentSong;
  Duration _currentDuration = Duration.zero;
  Duration _currentPosition = Duration.zero;
  bool _isPlaying = false;
  bool _shuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.off;
  Timer? _positionTimer;
  final StreamController<PositionData> _positionController = StreamController.broadcast();

  bool _isScanning = false;
  final SharedPreferences _prefs;
  String _searchQuery = '';

  static const String _prefSongsKey = 'musix_all_songs';
  static const String _prefIndexKey = 'musix_current_index';
  static const String _prefPositionKey = 'musix_position';

  List<AudioMetadata> get filteredSongs => _filteredSongs;
  bool get isScanning => _isScanning;
  String get searchQuery => _searchQuery;
  AudioMetadata? get currentSong => _currentSong;
  bool get isPlaying => _isPlaying;
  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;
  Duration get currentDuration => _currentDuration;
  Duration get currentPosition => _currentPosition;
  bool get hasPrevious => _orderPos > 0 || _repeatMode == RepeatMode.all;
  bool get hasNext => _orderPos + 1 < _playOrder.length || _repeatMode == RepeatMode.all;
  int? get currentDisplayIndex => _currentSong == null ? null : _playableSongs.indexOf(_currentSong!) + 1;

  Stream<PositionData> get positionDataStream => _positionController.stream;
  Stream<Float32List> get fftStream =>
      _soloud.audioVisualizationEvents.map((d) => d.fftData ?? Float32List(0));

  PlaybackProvider(this._prefs) {
    _initEngine();
    _loadInitialState();
  }

  Future<void> _initEngine() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('Audio session config error: $e');
    }
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init();
      }
      _soloud.setVisualizationEnabled(true);
    } catch (e) {
      debugPrint('SoLoud init error: $e');
    }
  }

  Future<void> _loadInitialState() async {
    final songsJson = _prefs.getString(_prefSongsKey);
    if (songsJson != null) {
      final List<dynamic> decoded = jsonDecode(songsJson);
      _allSongs.clear();
      _allSongs.addAll(decoded.map((e) => AudioMetadata.fromJson(e)));
      _applyFilter();
      _updatePlayableSongs(_allSongs);
    }
    notifyListeners();
    _autoScanLibrary();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    if (_searchQuery.isEmpty) {
      _filteredSongs = List.from(_allSongs);
    } else {
      _filteredSongs = _allSongs
          .where((song) => song.title.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
  }

  Future<void> _autoScanLibrary() async {
    if (_isScanning) return;
    _isScanning = true;
    notifyListeners();

    try {
      final docsDir = await pp.getApplicationDocumentsDirectory();
      final List<AudioMetadata> foundSongs = [];

      if (await docsDir.exists()) {
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
      }

      // Always trust the fresh scan: cached paths reference the app's sandbox
      // container UUID, which changes across rebuilds/reinstalls on iOS, so a
      // matching count doesn't mean the cached paths are still valid.
      final samePaths = foundSongs.length == _allSongs.length &&
          foundSongs.every((s) => _allSongs.any((a) => a.filePath == s.filePath));
      if (!samePaths) {
        _allSongs.clear();
        _allSongs.addAll(foundSongs);
        _applyFilter();
        await _prefs.setString(_prefSongsKey, jsonEncode(_allSongs.map((e) => e.toJson()).toList()));
        _updatePlayableSongs(_allSongs);
      }
    } catch (e) {
      debugPrint('Library scan error: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

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
          if (!file.path!.startsWith(docsDir.path)) {
            final sourceFile = File(file.path!);
            await sourceFile.copy(newPath);
            try {
              if (await sourceFile.exists()) {
                await sourceFile.delete();
              }
            } catch (e) {
              debugPrint('Note: System handled or cloud-synced files do not allow direct app deletion: $e');
            }
          }
        }
      }
      await _autoScanLibrary();
    }
  }

  void _updatePlayableSongs(List<AudioMetadata> songs) {
    _playableSongs = songs.where((s) => File(s.filePath).existsSync()).toList();
    _rebuildOrder(keepCurrent: true);
    notifyListeners();
  }

  void _rebuildOrder({bool keepCurrent = false}) {
    final indices = List<int>.generate(_playableSongs.length, (i) => i);
    if (_shuffleEnabled) {
      indices.shuffle();
    }
    final currentIndex = keepCurrent && _currentSong != null ? _playableSongs.indexOf(_currentSong!) : -1;
    if (currentIndex != -1) {
      indices
        ..remove(currentIndex)
        ..insert(0, currentIndex);
      _orderPos = 0;
    } else {
      _orderPos = -1;
    }
    _playOrder = indices;
  }

  void setShuffleEnabled(bool enabled) {
    if (_shuffleEnabled == enabled) return;
    _shuffleEnabled = enabled;
    _rebuildOrder(keepCurrent: true);
    notifyListeners();
  }

  void cycleRepeatMode() {
    _repeatMode = switch (_repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    notifyListeners();
  }

  Future<void> playTrack(AudioMetadata track) async {
    final songIndex = _playableSongs.indexWhere((s) => s.filePath == track.filePath);
    if (songIndex == -1) {
      debugPrint('playTrack: Song not found in playable list');
      return;
    }
    var orderPos = _playOrder.indexOf(songIndex);
    if (orderPos == -1) {
      _rebuildOrder();
      orderPos = _playOrder.indexOf(songIndex);
    }
    _orderPos = orderPos;
    await _playAtOrderPos();
  }

  /// Resumes playback, or starts the first track if nothing has been
  /// selected yet (e.g. a fresh app launch before any tap).
  Future<void> playOrResume() async {
    if (_currentHandle == null) {
      if (_playOrder.isEmpty) _rebuildOrder();
      if (_playOrder.isEmpty) return;
      if (_orderPos == -1) _orderPos = 0;
      await _playAtOrderPos();
    } else {
      _soloud.setPause(_currentHandle!, false);
      _isPlaying = true;
      notifyListeners();
    }
  }

  void pause() {
    if (_currentHandle != null) {
      _soloud.setPause(_currentHandle!, true);
    }
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> stop() async {
    _positionTimer?.cancel();
    if (_currentHandle != null) {
      await _soloud.stop(_currentHandle!);
    }
    _currentHandle = null;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  void seek(Duration position) {
    if (_currentHandle != null) {
      _soloud.seek(_currentHandle!, position);
      _currentPosition = position;
    }
  }

  Future<void> next() async {
    if (_repeatMode == RepeatMode.one) {
      await _playAtOrderPos();
      return;
    }
    if (_orderPos + 1 < _playOrder.length) {
      _orderPos++;
      await _playAtOrderPos();
    } else if (_repeatMode == RepeatMode.all && _playOrder.isNotEmpty) {
      _orderPos = 0;
      await _playAtOrderPos();
    } else {
      await stop();
    }
  }

  Future<void> previous() async {
    if (_currentPosition > const Duration(seconds: 3)) {
      seek(Duration.zero);
      return;
    }
    if (_orderPos > 0) {
      _orderPos--;
      await _playAtOrderPos();
    } else if (_repeatMode == RepeatMode.all && _playOrder.isNotEmpty) {
      _orderPos = _playOrder.length - 1;
      await _playAtOrderPos();
    } else {
      seek(Duration.zero);
    }
  }

  Future<void> _playAtOrderPos() async {
    if (_orderPos < 0 || _orderPos >= _playOrder.length) return;
    final song = _playableSongs[_playOrder[_orderPos]];
    await _loadAndPlay(song);
  }

  Future<void> _loadAndPlay(AudioMetadata song) async {
    _positionTimer?.cancel();
    final oldHandle = _currentHandle;
    final oldSource = _currentSource;
    _currentHandle = null;
    try {
      final source = await _soloud.loadFile(song.filePath);
      final handle = _soloud.play(source);
      _currentSource = source;
      _currentHandle = handle;
      _currentDuration = _soloud.getLength(source);
      _currentPosition = Duration.zero;
      _currentSong = song;
      _isPlaying = true;
      _prefs.setInt(_prefIndexKey, _playableSongs.indexOf(song));
      _positionController.add(PositionData(Duration.zero, _currentDuration, _currentDuration));
      _startPositionTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('_loadAndPlay error: $e');
    }
    if (oldHandle != null) {
      await _soloud.stop(oldHandle);
    }
    if (oldSource != null) {
      await _soloud.disposeSource(oldSource);
    }
  }

  void _startPositionTimer() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final handle = _currentHandle;
      if (handle == null) return;
      if (!_soloud.getIsValidVoiceHandle(handle)) {
        _positionTimer?.cancel();
        next();
        return;
      }
      _currentPosition = _soloud.getPosition(handle);
      _prefs.setInt(_prefPositionKey, _currentPosition.inMilliseconds);
      _positionController.add(PositionData(_currentPosition, _currentDuration, _currentDuration));
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _positionController.close();
    super.dispose();
  }
}
