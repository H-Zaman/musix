import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:musix/config/api_config.dart';
import 'package:musix/models/youtube_job.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

/// Backend contract used by the downloader; fake it in tests.
abstract interface class YoutubeApi {
  Future<YoutubeJob> createJob(String url);
  Future<YoutubeJob> getJobStatus(String jobId);
  Future<void> cancelJob(String jobId);
  Future<File> downloadMp3(
    YoutubeJob job, {
    void Function(double fraction)? onProgress,
  });
  String get baseUrl;
  String get apiKey;

  /// Points the client at another backend / key at runtime.
  void configure({String? baseUrl, String? apiKey});

  /// Null when the backend is reachable and accepts our key, else why not.
  Future<String?> checkConnection();
  void dispose();
}

class YoutubeApiService implements YoutubeApi {
  late final Dio _dio;
  String _baseUrl = ApiConfig.baseUrl;
  String _apiKey = ApiConfig.apiKey;

  @override
  String get baseUrl => _baseUrl;
  @override
  String get apiKey => _apiKey;

  @override
  void configure({String? baseUrl, String? apiKey}) {
    if (baseUrl != null && baseUrl.isNotEmpty) _baseUrl = baseUrl;
    if (apiKey != null) _apiKey = apiKey;
    _applyConfig();
  }

  void _applyConfig() {
    _dio.options.baseUrl = _baseUrl;
    if (_apiKey.isEmpty) {
      _dio.options.headers.remove('x-api-key');
    } else {
      _dio.options.headers['x-api-key'] = _apiKey;
    }
  }

  YoutubeApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    _applyConfig();

    if (kDebugMode) {
      _dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
          maxWidth: 90,
        ),
      );
    }
  }

  @override
  Future<YoutubeJob> createJob(String url) async {
    try {
      final response = await _dio.post('/api/jobs', data: {'url': url});
      return YoutubeJob.fromJson(response.data);
    } on DioException catch (e) {
      throw HttpException('Failed to create job: ${e.message}');
    }
  }

  @override
  Future<YoutubeJob> getJobStatus(String jobId) async {
    try {
      final response = await _dio.get('/api/jobs/$jobId');
      return YoutubeJob.fromJson(response.data);
    } on DioException catch (e) {
      throw HttpException('Failed to get job status: ${e.message}');
    }
  }

  @override
  Future<void> cancelJob(String jobId) async {
    try {
      await _dio.delete('/api/jobs/$jobId');
    } on DioException catch (e) {
      throw HttpException('Failed to cancel job: ${e.message}');
    }
  }

  @override
  Future<File> downloadMp3(
    YoutubeJob job, {
    void Function(double fraction)? onProgress,
  }) async {
    final downloadUrl = job.downloadUrl;
    if (downloadUrl == null) {
      throw Exception('Download URL is missing');
    }

    final base = Uri.parse(_baseUrl);
    final resolved = base.resolve(downloadUrl);
    // The backend may hand back an absolute URL; only follow our own host.
    if (resolved.host != base.host || resolved.port != base.port) {
      throw HttpException(
        'Refusing download from foreign host: ${resolved.host}',
      );
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final filePath = p.join(docsDir.path, safeFilename(job));
    final file = File(filePath);

    try {
      await _dio.downloadUri(
        resolved,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
        // Dio applies receiveTimeout per chunk wait; allow slow links.
        options: Options(receiveTimeout: const Duration(minutes: 2)),
      );
      return file;
    } catch (e) {
      if (await file.exists()) {
        await file.delete();
      }
      if (e is DioException) {
        throw HttpException('Failed to download MP3: ${e.message}');
      }
      rethrow;
    }
  }

  /// Backend-supplied names are untrusted: keep only a sanitized basename,
  /// force `.mp3`, and prefix the job id so downloads never overwrite
  /// existing files.
  @visibleForTesting
  static String safeFilename(YoutubeJob job) {
    final base = p
        .basenameWithoutExtension(job.filename ?? job.id)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'^\.+'), '');
    final name = base.isEmpty ? 'download' : base;
    return '${job.id}_$name.mp3';
  }

  @override
  Future<String?> checkConnection() async {
    try {
      await _dio.get('/health');
    } on DioException catch (e) {
      return 'Cannot reach $_baseUrl (${e.type.name})';
    }
    try {
      // An unknown job id: 404 means we got past the API-key check.
      await _dio.get('/api/jobs/_ping');
      return null;
    } on DioException catch (e) {
      return switch (e.response?.statusCode) {
        404 => null,
        401 => 'Backend reachable, but the API key was rejected',
        final code => 'Backend answered ${code ?? e.type.name}',
      };
    }
  }

  @override
  void dispose() {
    _dio.close();
  }
}
