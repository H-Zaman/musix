enum YoutubeJobStatus {
  queued,
  fetchingMetadata,
  downloading,
  converting,
  completed,
  failed,
  cancelled,
}

class YoutubeJob {
  final String id;
  final YoutubeJobStatus status;
  final String? title;
  final double progress;
  final String? speed;
  final String? eta;
  final String? error;
  final String? filename;
  final String? downloadUrl;

  /// Free-form status line (e.g. a retry notice); overrides [statusText].
  final String? detail;

  YoutubeJob({
    required this.id,
    required this.status,
    this.title,
    this.progress = 0,
    this.speed,
    this.eta,
    this.error,
    this.filename,
    this.downloadUrl,
    this.detail,
  });

  factory YoutubeJob.fromJson(Map<String, dynamic> json) {
    return YoutubeJob(
      id: json['id'],
      status: _parseStatus(json['status']),
      title: json['title'],
      progress: (json['progress'] ?? 0).toDouble(),
      speed: json['speed'],
      eta: json['eta'],
      error: json['error'],
      filename: json['filename'],
      downloadUrl: json['download_url'],
    );
  }

  static YoutubeJobStatus _parseStatus(String status) {
    switch (status) {
      case 'queued':
        return YoutubeJobStatus.queued;
      case 'fetching_metadata':
        return YoutubeJobStatus.fetchingMetadata;
      case 'downloading':
        return YoutubeJobStatus.downloading;
      case 'converting':
        return YoutubeJobStatus.converting;
      case 'completed':
        return YoutubeJobStatus.completed;
      case 'failed':
        return YoutubeJobStatus.failed;
      case 'cancelled':
        return YoutubeJobStatus.cancelled;
      default:
        return YoutubeJobStatus.failed;
    }
  }

  bool get isFinal =>
      status == YoutubeJobStatus.completed ||
      status == YoutubeJobStatus.failed ||
      status == YoutubeJobStatus.cancelled;

  String get statusText {
    if (detail != null) return detail!.toUpperCase();
    switch (status) {
      case YoutubeJobStatus.queued:
        return 'QUEUED...';
      case YoutubeJobStatus.fetchingMetadata:
        return 'FETCHING METADATA...';
      case YoutubeJobStatus.downloading:
        return 'DOWNLOADING...';
      case YoutubeJobStatus.converting:
        return 'CONVERTING TO MP3...';
      case YoutubeJobStatus.completed:
        return 'COMPLETED';
      case YoutubeJobStatus.failed:
        return 'FAILED';
      case YoutubeJobStatus.cancelled:
        return 'CANCELLED';
    }
  }
}
