import 'package:shared_preferences/shared_preferences.dart';

/// Where the API lives, changeable at runtime.
///
/// The base URL used to be a compile-time constant, which meant a rebuild every
/// time the server moved — painful when it's a tunnel whose URL changes on each
/// restart. Now it's a value you can set from the app and it sticks.
///
/// Resolution order: whatever was saved in the app → `--dart-define=API_BASE_URL`
/// → the deployed API.
class ApiConfig {
  static const _prefsKey = 'api_base_url';
  static const _trellisPrefsKey = 'trellis_base_url';

  /// The deployed API. Overridable at build time with
  /// `--dart-define=API_BASE_URL=http://localhost:8000` for local work, or at
  /// runtime from the Server field on the dev login screen.
  static const String compiledDefault = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://favorly-swart.vercel.app',
  );

  /// The agent + graph service (recommendations, needs, favor reviews). It is
  /// a separate deployment from the errand API because it can't run serverless
  /// — background worker, connection pool, SSE.
  static const String trellisCompiledDefault = String.fromEnvironment(
    'TRELLIS_BASE_URL',
    defaultValue: 'https://favorly-agents.vercel.app',
  );

  static String _baseUrl = compiledDefault;
  static String _trellisBaseUrl = trellisCompiledDefault;

  /// The URL requests go to. Never has a trailing slash.
  static String get baseUrl => _baseUrl;

  /// True when the user overrode the compiled-in default.
  static bool get isOverridden => _baseUrl != compiledDefault;

  /// Where the agent + graph service lives. Never has a trailing slash.
  static String get trellisBaseUrl => _trellisBaseUrl;

  static bool get isTrellisOverridden =>
      _trellisBaseUrl != trellisCompiledDefault;

  static String _normalize(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return compiledDefault;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Call once before runApp.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.isNotEmpty) _baseUrl = _normalize(saved);
      final savedTrellis = prefs.getString(_trellisPrefsKey);
      if (savedTrellis != null && savedTrellis.isNotEmpty) {
        _trellisBaseUrl = _normalize(savedTrellis);
      }
    } catch (_) {
      // No storage (first run, restricted platform) — the default still works.
    }
  }

  static Future<void> set(String raw) async {
    _baseUrl = _normalize(raw);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _baseUrl);
    } catch (_) {}
  }

  static Future<void> setTrellis(String raw) async {
    _trellisBaseUrl = raw.trim().isEmpty
        ? trellisCompiledDefault
        : _normalize(raw);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_trellisPrefsKey, _trellisBaseUrl);
    } catch (_) {}
  }

  /// Back to the compiled-in defaults.
  static Future<void> reset() async {
    _baseUrl = compiledDefault;
    _trellisBaseUrl = trellisCompiledDefault;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await prefs.remove(_trellisPrefsKey);
    } catch (_) {}
  }
}
