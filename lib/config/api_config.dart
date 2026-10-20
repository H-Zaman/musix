class ApiConfig {
  /// Override at build time: `--dart-define=API_BASE_URL=https://host`.
  /// The default only works in a simulator; on a physical phone point it at
  /// the machine running the backend (iOS allows plain http on the local
  /// network only).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:10000',
  );

  /// True when a backend was configured at build time.
  static const bool hasBackend = bool.hasEnvironment('API_BASE_URL');

  /// Optional `--dart-define=API_KEY=...`; sent as X-API-Key when non-empty.
  static const String apiKey = String.fromEnvironment('API_KEY');
}
