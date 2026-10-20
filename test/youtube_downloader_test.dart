import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musix/models/youtube_job.dart';
import 'package:musix/providers/youtube_downloader_provider.dart';
import 'package:musix/services/youtube_api_service.dart';

class FakeYoutubeApi implements YoutubeApi {
  final List<YoutubeJobStatus> script;
  final cancelled = <String>[];
  Object? downloadError;
  var _polls = 0;

  FakeYoutubeApi(this.script);

  YoutubeJob _job(YoutubeJobStatus s) => YoutubeJob(
        id: 'job1',
        status: s,
        downloadUrl: s == YoutubeJobStatus.completed ? '/api/jobs/job1/download' : null,
      );

  @override
  Future<YoutubeJob> createJob(String url) async => _job(YoutubeJobStatus.queued);

  @override
  Future<YoutubeJob> getJobStatus(String jobId) async =>
      _job(script[_polls < script.length ? _polls++ : script.length - 1]);

  @override
  Future<void> cancelJob(String jobId) async => cancelled.add(jobId);

  @override
  Future<File> downloadMp3(YoutubeJob job, {void Function(double)? onProgress}) async {
    if (downloadError != null) throw downloadError!;
    onProgress?.call(1);
    return File('/tmp/${job.id}.mp3');
  }

  @override
  void dispose() {}
}

YoutubeDownloaderProvider _provider(FakeYoutubeApi api, {Future<void> Function()? onDownloaded}) =>
    YoutubeDownloaderProvider(
      api: api,
      onDownloaded: onDownloaded ?? () async {},
      listenForShares: false,
      pollDelay: Duration.zero,
    );

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
    YoutubeJob job(String? name) =>
        YoutubeJob(id: 'j1', status: YoutubeJobStatus.completed, filename: name);

    test('strips traversal and forces an id-prefixed .mp3', () {
      final name = YoutubeApiService.safeFilename(job('../../etc/passwd'));
      expect(name, 'j1_passwd.mp3');
      expect(name.contains('/'), isFalse);
    });

    test('falls back when the backend sends no name', () {
      expect(YoutubeApiService.safeFilename(job(null)), 'j1_j1.mp3');
    });
  });

  group('YoutubeDownloaderProvider', () {
    test('completes: polls, downloads, then triggers a library rescan', () async {
      var rescans = 0;
      final p = _provider(
        FakeYoutubeApi([YoutubeJobStatus.downloading, YoutubeJobStatus.completed]),
        onDownloaded: () async => rescans++,
      );

      await p.startJob('https://youtu.be/abc');

      expect(p.state, DownloaderState.completed);
      expect(p.downloadedFile?.path, '/tmp/job1.mp3');
      expect(rescans, 1);
    });

    test('rejects an invalid URL without calling the backend', () async {
      final api = FakeYoutubeApi([]);
      final p = _provider(api);

      await p.startJob('https://evil.com/x');

      expect(p.state, DownloaderState.failed);
      expect(api.cancelled, isEmpty);
    });

    test('surfaces a failed download as an error state', () async {
      final api = FakeYoutubeApi([YoutubeJobStatus.completed])
        ..downloadError = const HttpException('boom');
      final p = _provider(api);

      await p.startJob('https://youtu.be/abc');

      expect(p.state, DownloaderState.failed);
    });

    test('cancel mid-poll leaves state idle and cancels the backend job', () async {
      final api = FakeYoutubeApi([YoutubeJobStatus.downloading]);
      final p = _provider(api);

      final running = p.startJob('https://youtu.be/abc');
      await Future<void>.delayed(Duration.zero);
      await p.cancelJob();
      await running;

      expect(p.state, DownloaderState.idle);
      expect(api.cancelled, ['job1']);
    });
  });
}
