class ApiConfig {
  /// Override at build time: `--dart-define=API_BASE_URL=https://host`.
  /// The default only works in a simulator; on a physical phone point it at
  /// the machine running the backend (iOS allows plain http on the local
  /// network only).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:10000',
  );
}
