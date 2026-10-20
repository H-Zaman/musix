import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:musix/config/api_config.dart';
import 'package:musix/models/youtube_job.dart';
import 'package:musix/services/on_device_downloader.dart';
import 'package:musix/services/youtube_api_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Downloads YouTube audio. It first tries to fetch it on the device itself
/// (no server, so YouTube sees the phone's connection); only if that fails
/// and a backend is configured does it fall back to the backend.
class YoutubeDownloaderProvider extends ChangeNotifier {
  static const _maxPollAttempts = 150; // 5 minutes at 2s
  static const _pollInterval = Duration(seconds: 2);
  static const _prefUrlKey = 'musix_backend_url';
  static const _prefKeyKey = 'musix_api_key';
  static const _localJobId = 'on-device';

  final YoutubeApi _api;
  final OnDeviceDownloads _onDevice;
  final SharedPreferences? _prefs;
  final Future<Directory> Function() _downloadDir;
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

  bool _testingBackend = false;
  bool? _backendOk;
  String? _backendStatus;

  DownloaderState get state => _state;
  YoutubeJob? get currentJob => _currentJob;
  String? get errorMessage => _errorMessage;
  File? get downloadedFile => _downloadedFile;
  double get downloadProgress => _downloadProgress;
  String get backendUrl => _backendConfigured ? _api.baseUrl : '';
  String get apiKey => _api.apiKey;
  bool get testingBackend => _testingBackend;
  bool? get backendOk => _backendOk;
  String? get backendStatus => _backendStatus;

  /// A backend counts only if it was set on purpose and isn't loopback:
  /// 127.0.0.1 / localhost on a phone is the phone itself.
  bool get _backendConfigured {
    final saved = _prefs?.getString(_prefUrlKey);
    if (saved == null && !ApiConfig.hasBackend) return false;
    final host = Uri.tryParse(_api.baseUrl)?.host ?? '';
    final loopback = host == '127.0.0.1' || host == 'localhost';
    return !loopback;
  }

  YoutubeDownloaderProvider({
    required this._onDownloaded,
    this._onOpenScreen,
    this._prefs,
    YoutubeApi? api,
    OnDeviceDownloads? onDevice,
    Future<Directory> Function()? downloadDir,
    bool listenForShares = true,
    @visibleForTesting this._pollDelay = _pollInterval,
  }) : _api = api ?? YoutubeApiService(),
       _onDevice = onDevice ?? OnDeviceDownloader(),
       _downloadDir = downloadDir ?? getApplicationDocumentsDirectory {
    _api.configure(
      baseUrl: _prefs?.getString(_prefUrlKey),
      apiKey: _prefs?.getString(_prefKeyKey),
    );
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
    if (previous != null && !previous.isFinal && previous.id != _localJobId) {
      unawaited(_cancelQuietly(previous.id));
    }
    _state = DownloaderState.creating;
    notifyListeners();

    // 1) On the device itself: no server involved.
    final failure = await _downloadOnDevice(gen, url);
    if (failure == null || gen != _generation) return;

    // 2) Fallback: the backend, only if one was configured.
    if (!_backendConfigured) {
      _setError(
        "Couldn't download this video on the device ($failure). "
        'Try again, or set a backend as a fallback below.',
      );
      return;
    }
    await _downloadViaBackend(gen, url, failure);
  }

  /// Returns null on success (or when superseded), else a short reason.
  Future<String?> _downloadOnDevice(int gen, String url) async {
    final clock = Stopwatch()..start();
    YoutubeJob local(
      YoutubeJobStatus status, {
      String? title,
      double progress = 0,
      String? speed,
      String? eta,
      String? detail,
    }) => YoutubeJob(
      id: _localJobId,
      status: status,
      title: title ?? _currentJob?.title,
      progress: progress,
      speed: speed,
      eta: eta,
      detail: detail,
    );

    _currentJob = local(YoutubeJobStatus.fetchingMetadata);
    _state = DownloaderState.processing;
    notifyListeners();

    try {
      final file = await _onDevice.download(
        url,
        destination: await _downloadDir(),
        isCancelled: () => gen != _generation,
        onTitle: (title) {
          if (gen != _generation) return;
          _currentJob = local(YoutubeJobStatus.downloading, title: title);
          notifyListeners();
        },
        onStatus: (message) {
          if (gen != _generation) return;
          // Speed is measured from the last status change.
          clock
            ..reset()
            ..start();
          _currentJob = local(YoutubeJobStatus.downloading, detail: message);
          notifyListeners();
        },
        onProgress: (received, total) {
          if (gen != _generation) return;
          final secs = clock.elapsedMilliseconds / 1000;
          final rate = secs > 0.5 ? received / secs : 0.0;
          final remaining = rate > 0
              ? ((total - received) / rate).round()
              : null;
          _currentJob = local(
            YoutubeJobStatus.downloading,
            progress: received * 100 / total,
            speed: rate > 0
                ? '${(rate / 1048576).toStringAsFixed(1)} MiB/S'
                : null,
            eta: remaining == null ? null : _mmss(remaining),
          );
          notifyListeners();
        },
        onConverting: () {
          if (gen != _generation) return;
          _currentJob = local(YoutubeJobStatus.converting, progress: 100);
          notifyListeners();
        },
      );
      if (gen != _generation) return null;
      _currentJob = local(YoutubeJobStatus.completed, progress: 100);
      _downloadedFile = file;
      _state = DownloaderState.completed;
      notifyListeners();
      await _onDownloaded();
      return null;
    } on DownloadCancelled {
      return null;
    } on Exception catch (e) {
      debugPrint('On-device download failed: $e');
      return e.toString().split('\n').first;
    }
  }

  static String _mmss(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _downloadViaBackend(
    int gen,
    String url,
    String deviceFailure,
  ) async {
    _currentJob = YoutubeJob(
      id: _localJobId,
      status: YoutubeJobStatus.queued,
      detail: 'Device download failed, trying the backend...',
    );
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
      debugPrint('Backend job failed: $e');
      if (gen == _generation) {
        _setError(
          "Couldn't download on this device ($deviceFailure), and the "
          'fallback backend at ${_api.baseUrl} is unreachable.',
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
    if (job.id != _localJobId) await _cancelQuietly(job.id);
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

  /// Saves the fallback backend settings; returns an error message, or null.
  String? saveBackend(String url, String key) {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) {
      // Empty means "no fallback backend": forget the saved settings.
      _prefs?.remove(_prefUrlKey);
      _prefs?.remove(_prefKeyKey);
      _api.configure(baseUrl: ApiConfig.baseUrl, apiKey: ApiConfig.apiKey);
      _backendOk = null;
      _backendStatus = null;
      notifyListeners();
      return null;
    }
    final uri = Uri.tryParse(cleaned);
    final valid =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    if (!valid) return 'Enter a full URL such as https://host';
    _api.configure(baseUrl: cleaned, apiKey: key.trim());
    _prefs?.setString(_prefUrlKey, cleaned);
    _prefs?.setString(_prefKeyKey, key.trim());
    _backendOk = null;
    _backendStatus = null;
    notifyListeners();
    return null;
  }

  Future<void> testBackend() async {
    _testingBackend = true;
    _backendOk = null;
    _backendStatus = null;
    notifyListeners();
    final problem = await _api.checkConnection();
    _testingBackend = false;
    _backendOk = problem == null;
    _backendStatus = problem ?? 'Connected';
    notifyListeners();
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
    _onDevice.dispose();
    super.dispose();
  }
}
