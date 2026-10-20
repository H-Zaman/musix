import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musix/models/youtube_job.dart';
import 'package:musix/providers/youtube_downloader_provider.dart';
import 'package:musix/services/on_device_downloader.dart';
import 'package:musix/services/shared_link_inbox.dart';
import 'package:musix/services/youtube_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeYoutubeApi implements YoutubeApi {
  final List<YoutubeJobStatus> script;
  final cancelled = <String>[];
  Object? downloadError;
  var created = 0;
  var _polls = 0;
  @override
  String baseUrl = 'http://fake';
  @override
  String apiKey = '';

  FakeYoutubeApi([this.script = const []]);

  YoutubeJob _job(YoutubeJobStatus s) => YoutubeJob(
    id: 'job1',
    status: s,
    downloadUrl: s == YoutubeJobStatus.completed
        ? '/api/jobs/job1/download'
        : null,
  );

  @override
  void configure({String? baseUrl, String? apiKey}) {
    if (baseUrl != null) this.baseUrl = baseUrl;
    if (apiKey != null) this.apiKey = apiKey;
  }

  @override
  Future<String?> checkConnection() async => null;

  @override
  Future<YoutubeJob> createJob(String url) async {
    created++;
    return _job(YoutubeJobStatus.queued);
  }

  @override
  Future<YoutubeJob> getJobStatus(String jobId) async =>
      _job(script[_polls < script.length ? _polls++ : script.length - 1]);

  @override
  Future<void> cancelJob(String jobId) async => cancelled.add(jobId);

  @override
  Future<File> downloadMp3(
    YoutubeJob job, {
    void Function(double)? onProgress,
  }) async {
    if (downloadError != null) throw downloadError!;
    onProgress?.call(1);
    return File('/tmp/${job.id}.mp3');
  }

  @override
  void dispose() {}
}

class FakeInbox implements SharedLinkInbox {
  String? pending;
  FakeInbox(this.pending);

  @override
  Future<String?> take() async {
    final p = pending;
    pending = null;
    return p;
  }
}

class FakeOnDevice implements OnDeviceDownloads {
  /// Throw this instead of returning a file.
  Object? failure;

  /// When set, the download waits for it (to test cancelling mid-way).
  Completer<void>? gate;
  var calls = 0;

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
    calls++;
    onTitle?.call('Song');
    onStatus?.call('Connecting');
    onProgress?.call(50, 100);
    await gate?.future;
    if (isCancelled?.call() ?? false) throw DownloadCancelled();
    if (failure != null) throw failure!;
    onConverting?.call();
    return File('${destination.path}/Song.opus');
  }

  @override
  void dispose() {}
}

Future<YoutubeDownloaderProvider> _provider(
  FakeYoutubeApi api,
  FakeOnDevice onDevice, {
  bool backendConfigured = false,
  Future<void> Function()? onDownloaded,
}) async {
  SharedPreferences.setMockInitialValues({
    if (backendConfigured) 'musix_backend_url': 'http://fake',
  });
  return YoutubeDownloaderProvider(
    api: api,
    onDevice: onDevice,
    prefs: await SharedPreferences.getInstance(),
    downloadDir: () async => Directory('/tmp'),
    onDownloaded: onDownloaded ?? () async {},
    listenForShares: false,
    pollDelay: Duration.zero,
  );
}

void main() {
  group('extractYoutubeUrl', () {
    test('normalizes a scheme-less link to https', () {
      expect(extractYoutubeUrl('youtu.be/abc123'), 'https://youtu.be/abc123');
    });

    test('finds the link inside shared text', () {
      expect(
        extractYoutubeUrl('Watch this https://www.youtube.com/watch?v=abc now'),
        'https://www.youtube.com/watch?v=abc',
      );
    });

    test('rejects non-YouTube hosts and plain text', () {
      expect(extractYoutubeUrl('https://evil.com/watch?v=abc'), isNull);
      expect(extractYoutubeUrl('hello'), isNull);
    });
  });

  group('safeFilename', () {
    YoutubeJob job(String? name) => YoutubeJob(
      id: 'j1',
      status: YoutubeJobStatus.completed,
      filename: name,
    );

    test('strips traversal and forces an id-prefixed .mp3', () {
      final name = YoutubeApiService.safeFilename(job('../../etc/passwd'));
      expect(name, 'j1_passwd.mp3');
      expect(name.contains('/'), isFalse);
    });

    test('falls back when the backend sends no name', () {
      expect(YoutubeApiService.safeFilename(job(null)), 'j1_j1.mp3');
    });
  });

  group('on-device first', () {
    test('downloads on the device and never touches the backend', () async {
      var rescans = 0;
      final api = FakeYoutubeApi();
      final p = await _provider(
        api,
        FakeOnDevice(),
        onDownloaded: () async => rescans++,
      );

      await p.startJob('https://youtu.be/abc');

      expect(p.state, DownloaderState.completed);
      expect(p.downloadedFile?.path, '/tmp/Song.opus');
      expect(p.currentJob?.title, 'Song');
      expect(rescans, 1);
      expect(api.created, 0);
    });

    test(
      'failure with no backend configured explains and stays on the device',
      () async {
        final api = FakeYoutubeApi();
        final p = await _provider(
          api,
          FakeOnDevice()..failure = DownloadFailed('blocked'),
        );

        await p.startJob('https://youtu.be/abc');

        expect(p.state, DownloaderState.failed);
        expect(p.errorMessage, contains('blocked'));
        expect(api.created, 0);
      },
    );

    test('a saved loopback URL is not a real fallback', () async {
      SharedPreferences.setMockInitialValues({
        'musix_backend_url': 'http://127.0.0.1:10000',
      });
      final api = FakeYoutubeApi();
      final p = YoutubeDownloaderProvider(
        api: api,
        onDevice: FakeOnDevice()..failure = DownloadFailed('blocked'),
        prefs: await SharedPreferences.getInstance(),
        downloadDir: () async => Directory('/tmp'),
        onDownloaded: () async {},
        listenForShares: false,
        pollDelay: Duration.zero,
      );

      await p.startJob('https://youtu.be/abc');

      expect(
        api.created,
        0,
        reason: '127.0.0.1 on a phone is the phone itself',
      );
      expect(p.backendUrl, isEmpty);
      expect(p.state, DownloaderState.failed);
    });

    test(
      'falls back to the configured backend when the device is refused',
      () async {
        var rescans = 0;
        final api = FakeYoutubeApi([
          YoutubeJobStatus.downloading,
          YoutubeJobStatus.completed,
        ]);
        final p = await _provider(
          api,
          FakeOnDevice()..failure = DownloadFailed('blocked'),
          backendConfigured: true,
          onDownloaded: () async => rescans++,
        );

        await p.startJob('https://youtu.be/abc');

        expect(p.state, DownloaderState.completed);
        expect(p.downloadedFile?.path, '/tmp/job1.mp3');
        expect(rescans, 1);
      },
    );

    test(
      'cancelling mid-download leaves state idle and skips the rescan',
      () async {
        var rescans = 0;
        final onDevice = FakeOnDevice()..gate = Completer<void>();
        final p = await _provider(
          FakeYoutubeApi(),
          onDevice,
          onDownloaded: () async => rescans++,
        );

        final running = p.startJob('https://youtu.be/abc');
        await Future<void>.delayed(Duration.zero);
        await p.cancelJob();
        onDevice.gate!.complete();
        await running;

        expect(p.state, DownloaderState.idle);
        expect(rescans, 0);
      },
    );
  });

  group('backend fallback path', () {
    Future<YoutubeDownloaderProvider> viaBackend(FakeYoutubeApi api) =>
        _provider(
          api,
          FakeOnDevice()..failure = DownloadFailed('blocked'),
          backendConfigured: true,
        );

    test('rejects an invalid URL without calling anything', () async {
      final api = FakeYoutubeApi();
      final onDevice = FakeOnDevice();
      final p = await _provider(api, onDevice);

      await p.startJob('https://evil.com/x');

      expect(p.state, DownloaderState.failed);
      expect(onDevice.calls, 0);
      expect(api.created, 0);
    });

    test('surfaces a failed backend download as an error state', () async {
      final api = FakeYoutubeApi([YoutubeJobStatus.completed])
        ..downloadError = const HttpException('boom');
      final p = await viaBackend(api);

      await p.startJob('https://youtu.be/abc');

      expect(p.state, DownloaderState.failed);
    });

    test(
      'cancel mid-poll leaves state idle and cancels the backend job',
      () async {
        final api = FakeYoutubeApi([YoutubeJobStatus.downloading]);
        final p = await viaBackend(api);

        final running = p.startJob('https://youtu.be/abc');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await p.cancelJob();
        await running;

        expect(p.state, DownloaderState.idle);
        expect(api.cancelled, ['job1']);
      },
    );
  });

  group('shared link inbox', () {
    Future<YoutubeDownloaderProvider> withInbox(
      FakeInbox inbox,
      FakeOnDevice onDevice,
    ) async {
      SharedPreferences.setMockInitialValues({});
      return YoutubeDownloaderProvider(
        api: FakeYoutubeApi(),
        onDevice: onDevice,
        inbox: inbox,
        prefs: await SharedPreferences.getInstance(),
        downloadDir: () async => Directory('/tmp'),
        onDownloaded: () async {},
        listenForShares: false,
        pollDelay: Duration.zero,
      );
    }

    test('a shared link starts the download and fills the field', () async {
      final onDevice = FakeOnDevice();
      final p = await withInbox(
        FakeInbox('Check this out https://youtu.be/abc123?si=x'),
        onDevice,
      );

      await p.checkSharedInbox();

      expect(p.lastUrl, 'https://youtu.be/abc123?si=x');
      expect(onDevice.calls, 1);
      expect(p.state, DownloaderState.completed);

      // one-shot: nothing left to replay
      await p.checkSharedInbox();
      expect(onDevice.calls, 1);
    });

    test('shared text without a YouTube link is ignored', () async {
      final onDevice = FakeOnDevice();
      final p = await withInbox(FakeInbox('hello there'), onDevice);

      await p.checkSharedInbox();

      expect(onDevice.calls, 0);
      expect(p.state, DownloaderState.idle);
    });
  });

  group('backend settings', () {
    test('rejects a malformed URL', () async {
      final p = await _provider(FakeYoutubeApi(), FakeOnDevice());
      expect(p.saveBackend('not a url', ''), isNotNull);
      expect(p.saveBackend('ftp://host', ''), isNotNull);
    });

    test('saves, trims and persists a valid URL and key', () async {
      final api = FakeYoutubeApi();
      final p = await _provider(api, FakeOnDevice());

      expect(p.saveBackend('  https://host.example/  ', ' k '), isNull);

      expect(api.baseUrl, 'https://host.example');
      expect(api.apiKey, 'k');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('musix_backend_url'), 'https://host.example');
    });
  });
}
