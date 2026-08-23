/// Backend base URL for the Vault API.
///
/// Override at build time with:
/// `flutter run --dart-define=API_BASE_URL=https://your-host`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:8787',
);
