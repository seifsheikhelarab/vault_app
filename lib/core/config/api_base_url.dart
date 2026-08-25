/// Backend base URL for the Vault API.
///
/// Override at build time with:
/// `flutter run --dart-define=API_BASE_URL=https://your-host`
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.1.12:8787',
);

/// Fails fast on release builds that would ship pointing at localhost or
/// over cleartext HTTP to a public host. Private LAN IPs (RFC1918) are
/// allowed so release-mode testing against a dev backend works.
void ensureApiBaseUrlValid({required bool isRelease}) {
  if (!isRelease) return;
  if (_isPrivateLanHost(apiBaseUrl)) return;
  if (!apiBaseUrl.startsWith('https://')) {
    throw StateError(
      'API_BASE_URL must be an https URL in release builds (got '
      '"$apiBaseUrl"). Build with --dart-define=API_BASE_URL=https://your-host',
    );
  }
}

bool _isPrivateLanHost(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  final match = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
      .firstMatch(host);
  if (match == null) return false;
  final a = int.parse(match.group(1)!);
  final b = int.parse(match.group(2)!);
  if (a == 10 || (a == 192 && b == 168)) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}
