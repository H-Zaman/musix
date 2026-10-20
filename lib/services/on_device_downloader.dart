import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:musix/services/debug_log.dart';
import 'package:musix/services/webm_opus_remuxer.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A failure the provider can recover from (e.g. by falling back).
class DownloadFailed implements Exception {
  final String message;
  DownloadFailed(this.message);
  @override
  String toString() => message;
}

class DownloadCancelled implements Exception {
  @override
  String toString() => 'Download cancelled';
}

/// Downloads a YouTube video's audio straight on the device (no backend), so
/// YouTube sees the phone's own connection instead of a datacenter IP.
abstract interface class OnDeviceDownloads {
  Future<File> download(
    String url, {
    required Directory destination,
    void Function(String title)? onTitle,
    void Function(int received, int total)? onProgress,
    VoidCallback? onConverting,
    void Function(String message)? onStatus,
    bool Function()? isCancelled,
  });

  void dispose();
}

class OnDeviceDownloader implements OnDeviceDownloads {
  OnDeviceDownloader({YoutubeExplode? yt}) : _yt = yt ?? YoutubeExplode();

  final YoutubeExplode _yt;

  /// A silent stream is treated as blocked and the next client is tried.
  static const _stallTimeout = Duration(seconds: 12);

  /// YouTube lookups that never answer must not hang the download forever.
  static const _stepTimeout = Duration(seconds: 25);

  /// Apple Vision Pro client identity. Since Aug 2026 YouTube demands a PO
  /// token for the media URLs of the androidVr and ios clients (manifest
  /// resolves, then the stream 403s or sends nothing), but still serves
  /// VISIONOS without one; yt-dlp made it its default for the same reason.
  /// Definition from youtube_explode_dart PR #389 (not yet released).
  static const _visionOs = YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
            '(KHTML, like Gecko) Version/26.0 Safari/605.1.15',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  /// YouTube serves different (and differently blocked) streams per client
  /// identity, so try visionOS first and keep the others as fallbacks in
  /// case YouTube changes its mind again.
  static final List<List<YoutubeApiClient>?> _clientOrder = [
    [_visionOs],
    null,
    [YoutubeApiClient.androidVr],
    [YoutubeApiClient.ios],
  ];

  @override
  Future<File> download(
    String url, {
    required Directory destination,
    void Function(String title)? onTitle,
    void Function(int received, int total)? onProgress,
    VoidCallback? onConverting,
    void Function(String message)? onStatus,
    bool Function()? isCancelled,
  }) async {
    final id = VideoId.parseVideoId(url);
    if (id == null) throw DownloadFailed('Not a YouTube video URL');

    final clock = Stopwatch()..start();
    DebugLog.add('download start id=$id');
    onStatus?.call('Looking up video...');
    final Video video;
    try {
      video = await _yt.videos.get(id).timeout(_stepTimeout);
    } catch (e) {
      DebugLog.add(
        'videos.get FAILED after ${clock.elapsedMilliseconds}ms: ${e.runtimeType}: $e',
      );
      rethrow;
    }
    DebugLog.add(
      'videos.get ok in ${clock.elapsedMilliseconds}ms: "${video.title}"',
    );
    onTitle?.call(video.title);

    Object? lastError;
    for (var i = 0; i < _clientOrder.length; i++) {
      final clients = _clientOrder[i];
      final tag = '${i + 1}/${_clientOrder.length}';
      onStatus?.call('Fetching stream info ($tag)...');
      DebugLog.add(
        'attempt $tag client=${clients == null ? 'default' : (clients.first.payload['context']['client']['clientName'])} at ${clock.elapsedMilliseconds}ms',
      );
      if (isCancelled?.call() ?? false) throw DownloadCancelled();
      try {
        final manifest = await _yt.videos.streamsClient
            .getManifest(id, ytClients: clients)
            .timeout(_stepTimeout);
        final stream = _bestOpus(manifest);
        DebugLog.add(
          'manifest ok at ${clock.elapsedMilliseconds}ms: ${manifest.audioOnly.length} audio streams, '
          'using ${stream.container.name} ${stream.bitrate} ${stream.size}',
        );
        onStatus?.call('Starting download ($tag)...');
        final webm = await _fetch(stream, onProgress, isCancelled);
        onConverting?.call();
        final ogg = await Isolate.run(() => remuxWebmOpusToOgg(webm));
        return await _save(destination, video.title, ogg);
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        DebugLog.add(
          'attempt $tag FAILED at ${clock.elapsedMilliseconds}ms: ${e.runtimeType}: $e',
        );
        lastError = e;
        onStatus?.call(
          'Attempt $tag failed (${_reason(e)}), trying another way...',
        );
      }
    }
    throw lastError ?? DownloadFailed('No client could fetch this video');
  }

  /// Short, human-readable cause for the status line.
  static String _reason(Object e) => switch (e) {
    TimeoutException() => 'no answer',
    DownloadFailed(:final message) => message,
    _ => e.runtimeType.toString(),
  };

  AudioOnlyStreamInfo _bestOpus(StreamManifest manifest) {
    final opus =
        manifest.audioOnly.where((s) => s.container.name == 'webm').toList()
          ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (opus.isEmpty) throw DownloadFailed('No WebM/Opus audio stream offered');
    return opus.first;
  }

  /// Collects the stream, giving up if no data arrives for [_stallTimeout].
  ///
  /// Not `await for ... .timeout()`: leaving that loop awaits the source's
  /// cancel, and the library's stream can be stuck inside a request that
  /// never answers, so the cancel (and the whole download) would hang.
  /// Here a stall completes the future immediately and the dead stream is
  /// cancelled in the background.
  Future<Uint8List> _fetch(
    AudioOnlyStreamInfo stream,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  ) {
    final total = stream.size.totalBytes;
    final buffer = BytesBuilder(copy: false);
    final clock = Stopwatch()..start();
    final done = Completer<Uint8List>();
    late final StreamSubscription<List<int>> sub;
    Timer? stallTimer;
    var nextLogAt = 0;

    void finish({Object? error, Uint8List? bytes}) {
      if (done.isCompleted) return;
      stallTimer?.cancel();
      unawaited(sub.cancel().then<void>((_) {}, onError: (Object _) {}));
      if (error != null) {
        done.completeError(error);
      } else {
        done.complete(bytes);
      }
    }

    void armStallTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(_stallTimeout, () {
        DebugLog.add(
          '  no data for ${_stallTimeout.inSeconds}s '
          '(received ${buffer.length}/$total) - giving up on this stream',
        );
        finish(error: TimeoutException('no data', _stallTimeout));
      });
    }

    sub = _yt.videos.streamsClient
        .get(stream)
        .listen(
          (chunk) {
            if (isCancelled?.call() ?? false) {
              finish(error: DownloadCancelled());
              return;
            }
            buffer.add(chunk);
            if (buffer.length >= nextLogAt) {
              DebugLog.add(
                '  received ${buffer.length}/$total bytes '
                'at ${clock.elapsedMilliseconds}ms',
              );
              nextLogAt = buffer.length + 1024 * 1024;
            }
            if (total > 0) onProgress?.call(buffer.length, total);
            armStallTimer();
          },
          onError: (Object e) => finish(error: e),
          onDone: () => finish(bytes: buffer.takeBytes()),
          cancelOnError: true,
        );
    armStallTimer();
    return done.future;
  }

  Future<File> _save(Directory dir, String title, Uint8List ogg) async {
    var base = title.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
    if (base.isEmpty) base = 'download';
    if (base.length > 100) base = base.substring(0, 100).trim();
    var path = p.join(dir.path, '$base.opus');
    for (var i = 1; await File(path).exists(); i++) {
      path = p.join(dir.path, '$base ($i).opus');
    }
    return File(path).writeAsBytes(ogg, flush: true);
  }

  @override
  void dispose() => _yt.close();
}
