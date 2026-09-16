import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:musix/models/youtube_job.dart';
import 'package:musix/services/youtube_api_service.dart';
import 'package:musix/musix.dart';
import 'package:musix/screens/youtube_downloader_screen.dart';
import 'package:share_plus/share_plus.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:musix/providers/playback_provider.dart';

enum DownloaderState {
  idle,
  creating,
  processing,
  downloadingFile,
  completed,
  failed,
}

class YoutubeDownloaderProvider extends ChangeNotifier {
  final YoutubeApiService _apiService = YoutubeApiService();
  final PlaybackProvider _playbackProvider;
  
  DownloaderState _state = DownloaderState.idle;
  YoutubeJob? _currentJob;
  String? _errorMessage;
  File? _downloadedFile;
  Timer? _pollingTimer;

  DownloaderState get state => _state;
  YoutubeJob? get currentJob => _currentJob;
  String? get errorMessage => _errorMessage;
  File? get downloadedFile => _downloadedFile;

  YoutubeDownloaderProvider(this._playbackProvider) {
    _initSharingListener();
  }

  void _initSharingListener() {
    // For sharing or opening urls/text while app is in background or foreground
    ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final url = _extractUrl(value.first.path);
        if (url != null) {
          startJob(url);
        }
      }
    }, onError: (err) {
      debugPrint("getMediaStream error: $err");
    });

    // For sharing or opening urls/text while app is closed. Must be reset
    // after handling, otherwise the same shared link replays on every
    // subsequent cold launch and silently restarts an old download job.
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        final url = _extractUrl(value.first.path);
        if (url != null) {
          startJob(url);
        }
      }
      ReceiveSharingIntent.instance.reset();
    });
  }

  String? _extractUrl(String text) {
    final urlRegExp = RegExp(
        r'((https?://)?(www\.)?(youtube\.com|youtu\.be|youtube\.com/shorts)/[^\s]+)');
    final match = urlRegExp.firstMatch(text);
    return match?.group(0);
  }

  void _navigateToDownloader() {
    final context = MusixApp.navigatorKey.currentContext;
    if (context != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const YoutubeDownloaderScreen()),
      );
    }
  }

  Future<void> startJob(String url) async {
    if (url.isEmpty || !url.contains('youtu')) {
      _setError('Please enter a valid YouTube URL');
      return;
    }

    _navigateToDownloader();
    _reset();
    _state = DownloaderState.creating;
    notifyListeners();

    try {
      _currentJob = await _apiService.createJob(url);
      _state = DownloaderState.processing;
      notifyListeners();
      _startPolling();
    } catch (e) {
      _setError('Failed to connect to backend. It might be waking up...');
    }
  }

  static const _maxPollAttempts = 300; // 5 minutes at 1s interval
  int _pollAttempts = 0;

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollAttempts = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_currentJob == null) {
        timer.cancel();
        return;
      }
      if (++_pollAttempts > _maxPollAttempts) {
        timer.cancel();
        _setError('Timed out waiting for the backend to finish processing');
        return;
      }

      try {
        final updatedJob = await _apiService.getJobStatus(_currentJob!.id);
        _currentJob = updatedJob;
        
        if (updatedJob.status == YoutubeJobStatus.completed) {
          timer.cancel();
          _downloadFile();
        } else if (updatedJob.status == YoutubeJobStatus.failed) {
          timer.cancel();
          _setError(updatedJob.error ?? 'Backend processing failed');
        } else if (updatedJob.status == YoutubeJobStatus.cancelled) {
          timer.cancel();
          _state = DownloaderState.idle;
        }
        
        notifyListeners();
      } catch (e) {
        debugPrint('Polling error: $e');
        // We don't stop on a single network error, just wait for next tick
      }
    });
  }

  Future<void> _downloadFile() async {
    if (_currentJob == null) return;
    
    _state = DownloaderState.downloadingFile;
    notifyListeners();

    try {
      _downloadedFile = await _apiService.downloadMp3(_currentJob!);
      _state = DownloaderState.completed;
      notifyListeners();
      
      // Trigger a rescan of the library so the new song shows up instantly
      // We wait a tiny bit to ensure File I/O is finalized by OS
      Future.delayed(const Duration(milliseconds: 500), () {
        _playbackProvider.rescanLibrary();
      });
    } catch (e) {
      _setError('Download failed while saving the file');
    }
  }

  Future<void> cancelJob() async {
    if (_currentJob == null) return;

    _pollingTimer?.cancel();
    final jobId = _currentJob!.id;
    _reset();
    notifyListeners();

    try {
      await _apiService.cancelJob(jobId);
    } catch (e) {
      debugPrint('Cancel request failed: $e');
    }
  }

  void shareFile() {
    if (_downloadedFile != null) {
      Share.shareXFiles([XFile(_downloadedFile!.path)]);
    }
  }

  void _setError(String message) {
    _state = DownloaderState.failed;
    _errorMessage = message;
    _pollingTimer?.cancel();
    notifyListeners();
  }

  void _reset() {
    _state = DownloaderState.idle;
    _currentJob = null;
    _errorMessage = null;
    _downloadedFile = null;
    _pollingTimer?.cancel();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _apiService.dispose();
    super.dispose();
  }
}
