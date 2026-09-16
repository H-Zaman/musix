import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:musix/config/api_config.dart';
import 'package:musix/models/youtube_job.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

class YoutubeApiService {
  late final Dio _dio;

  YoutubeApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

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

  Future<YoutubeJob> createJob(String url) async {
    try {
      print(1);
      final response = await _dio.post('/api/jobs', data: {'url': url});
      return YoutubeJob.fromJson(response.data);
    } on DioException catch (e) {
      print(2);
      throw HttpException('Failed to create job: ${e.message}');
    }
  }

  Future<YoutubeJob> getJobStatus(String jobId) async {
    try {
      final response = await _dio.get('/api/jobs/$jobId');
      return YoutubeJob.fromJson(response.data);
    } on DioException catch (e) {
      throw HttpException('Failed to get job status: ${e.message}');
    }
  }

  Future<void> cancelJob(String jobId) async {
    try {
      await _dio.delete('/api/jobs/$jobId');
    } on DioException catch (e) {
      throw HttpException('Failed to cancel job: ${e.message}');
    }
  }

  Future<File> downloadMp3(YoutubeJob job) async {
    if (job.downloadUrl == null) {
      throw Exception('Download URL is missing');
    }

    String fullUrl = job.downloadUrl!;
    // If relative, Dio will automatically prepend baseUrl if we use / prefix or if we use full URL logic
    if (!fullUrl.startsWith('http')) {
      fullUrl = '${ApiConfig.baseUrl}$fullUrl';
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final filename = job.filename ?? '${job.id}.mp3';
    final sanitizedFilename = _sanitizeFilename(filename);
    final filePath = p.join(docsDir.path, sanitizedFilename);
    final file = File(filePath);

    try {
      await _dio.download(
        fullUrl,
        filePath,
        options: Options(responseType: ResponseType.stream),
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

  String _sanitizeFilename(String filename) {
    return filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<bool> checkHealth() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }

  void dispose() {
    _dio.close();
  }
}
