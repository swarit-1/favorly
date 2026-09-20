/// Dev-time config. No auth yet, so the "current user" and circle are
/// hardcoded to the seeded demo data (backend/seed/demo_circle.json) --
/// replace once real sign-in exists.
library;

class AppConfig {
  /// iOS simulator can reach the host machine at `localhost`. Android's
  /// emulator needs `10.0.2.2` instead; a physical device needs your
  /// machine's LAN IP. Override with `--dart-define=API_BASE_URL=...`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // The live "Maple St · Building B" circle in Supabase.
  static const String demoCircleId = '6829dad5-2e30-4adf-911b-0c91e254013f';
  static const String currentUserId = '61f48091-a3d3-453a-83ec-252352c16ec4'; // Ana (Shopper)
}
