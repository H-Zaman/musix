import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:musix/config/api_config.dart';
import 'package:musix/models/youtube_job.dart';
import 'package:musix/services/youtube_api_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

enum DownloaderState {
  idle,
  creating,
  processing,
  downloadingFile,
  completed,
  failed,
}

const _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
};

/// Pulls the first YouTube link out of [text] and returns it as a validated
/// https URL, or null when there is none.
String? extractYoutubeUrl(String text) {
  final match = RegExp(
    r'(?:https?://)?(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be)/[^\s]+',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;

  var candidate = match.group(0)!;
  if (!candidate.toLowerCase().startsWith('http')) {
    candidate = 'https://$candidate';
  }
  final uri = Uri.tryParse(candidate);
  if (uri == null || !_youtubeHosts.contains(uri.host.toLowerCase())) {
    return null;
  }
  return uri.replace(scheme: 'https').toString();
}

class YoutubeDownloaderProvider extends ChangeNotifier {
  static const _maxPollAttempts = 150; // 5 minutes at 2s
  static const _pollInterval = Duration(seconds: 2);

  final YoutubeApi _api;
  final Future<void> Function() _onDownloaded;
  final VoidCallback? _onOpenScreen;
  final Duration _pollDelay;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;

  DownloaderState _state = DownloaderState.idle;
  YoutubeJob? _currentJob;
  String? _errorMessage;
  File? _downloadedFile;
  double _downloadProgress = 0;
  // Bumped on every reset/dispose; async work compares it after each await
  // so a cancelled or replaced job can't write stale state.
  int _generation = 0;
  bool _disposed = false;

  DownloaderState get state => _state;
  YoutubeJob? get currentJob => _currentJob;
  String? get errorMessage => _errorMessage;
  File? get downloadedFile => _downloadedFile;
  double get downloadProgress => _downloadProgress;

  YoutubeDownloaderProvider({
    required this._onDownloaded,
    this._onOpenScreen,
    YoutubeApi? api,
    bool listenForShares = true,
    @visibleForTesting this._pollDelay = _pollInterval,
  }) : _api = api ?? YoutubeApiService() {
    if (listenForShares) _initSharingListener();
  }

  void _initSharingListener() {
    // Links shared while the app is in background or foreground.
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleShared,
      onError: (Object err) => debugPrint('getMediaStream error: $err'),
    );

    // Links shared while the app is closed. Must be reset after handling,
    // otherwise the same link replays on every cold launch.
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((value) {
          _handleShared(value);
          ReceiveSharingIntent.instance.reset();
        })
        .catchError((Object err) {
          debugPrint('getInitialMedia error: $err');
        });
  }

  void _handleShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final url = extractYoutubeUrl(files.first.path);
    if (url != null) startJob(url);
  }

  Future<void> startJob(String input) async {
    final url = extractYoutubeUrl(input);
    if (url == null) {
      _setError('Please enter a valid YouTube URL');
      return;
    }

    final previous = _currentJob;
    _onOpenScreen?.call();
    final gen = _reset();
    if (previous != null && !previous.isFinal) {
      unawaited(_cancelQuietly(previous.id));
    }
    _state = DownloaderState.creating;
    notifyListeners();

    try {
      final job = await _api.createJob(url);
      if (gen != _generation) {
        unawaited(_cancelQuietly(job.id));
        return;
      }
      _currentJob = job;
      _state = DownloaderState.processing;
      notifyListeners();
      await _pollLoop(gen, job.id);
    } on Exception catch (e) {
      debugPrint('startJob failed: $e');
      if (gen == _generation) {
        _setError(
          'Could not reach the backend at ${ApiConfig.baseUrl}. '
          'It may be offline or waking up.',
        );
      }
    }
  }

  // Chained (not Timer.periodic) so a slow status call can't overlap the
  // next tick.
  Future<void> _pollLoop(int gen, String jobId) async {
    for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
      await Future<void>.delayed(_pollDelay);
      if (gen != _generation) return;
      try {
        final job = await _api.getJobStatus(jobId);
        if (gen != _generation) return;
        _currentJob = job;
        switch (job.status) {
          case YoutubeJobStatus.completed:
            notifyListeners();
            await _downloadFile(gen, job);
            return;
          case YoutubeJobStatus.failed:
            _setError(job.error ?? 'Backend processing failed');
            return;
          case YoutubeJobStatus.cancelled:
            _state = DownloaderState.idle;
            notifyListeners();
            return;
          case YoutubeJobStatus.queued:
          case YoutubeJobStatus.fetchingMetadata:
          case YoutubeJobStatus.downloading:
          case YoutubeJobStatus.converting:
            notifyListeners();
        }
      } on Exception catch (e) {
        // A single network error shouldn't end the job; retry next tick.
        debugPrint('Polling error: $e');
      }
    }
    if (gen == _generation) {
      _setError('Timed out waiting for the backend to finish processing');
    }
  }

  Future<void> _downloadFile(int gen, YoutubeJob job) async {
    _state = DownloaderState.downloadingFile;
    _downloadProgress = 0;
    notifyListeners();

    try {
      final file = await _api.downloadMp3(
        job,
        onProgress: (fraction) {
          if (gen != _generation) return;
          _downloadProgress = fraction;
          notifyListeners();
        },
      );
      if (gen != _generation) return;
      _downloadedFile = file;
      _state = DownloaderState.completed;
      notifyListeners();
      // Rescan so the new song shows up immediately.
      await _onDownloaded();
    } on Exception catch (e) {
      debugPrint('Download failed: $e');
      if (gen == _generation) {
        _setError('Download failed while saving the file');
      }
    }
  }

  Future<void> cancelJob() async {
    final job = _currentJob;
    if (job == null) return;
    _reset();
    notifyListeners();
    await _cancelQuietly(job.id);
  }

  Future<void> _cancelQuietly(String jobId) async {
    try {
      await _api.cancelJob(jobId);
    } on Exception catch (e) {
      debugPrint('Cancel request failed: $e');
    }
  }

  void shareFile() {
    final file = _downloadedFile;
    if (file != null) {
      Share.shareXFiles([XFile(file.path)]);
    }
  }

  void _setError(String message) {
    _state = DownloaderState.failed;
    _errorMessage = message;
    notifyListeners();
  }

  int _reset() {
    _state = DownloaderState.idle;
    _currentJob = null;
    _errorMessage = null;
    _downloadedFile = null;
    _downloadProgress = 0;
    return ++_generation;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _shareSub?.cancel();
    _api.dispose();
    super.dispose();
  }
}
