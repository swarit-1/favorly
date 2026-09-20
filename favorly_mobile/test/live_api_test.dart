// Hits the real deployed API, so it's skipped by default. Run it when you
// want to confirm the app's client code still matches what's deployed:
//
//   flutter test test/live_api_test.dart --run-skipped

import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/services/api_client.dart';
import 'package:favorly_mobile/services/api_config.dart';

void main() {
  group('deployed API', () {
    test('compiled default points at the deployed host', () {
      expect(ApiConfig.compiledDefault, startsWith('https://'));
    });

    test('login returns a token for a seeded account', () async {
      final res = await ApiClient.login(
        email: 'jordan.reyes@favorly.test',
        password: 'favorly-dev-2024',
      );
      expect(res['name'], 'Jordan Reyes');
      expect(res['access_token'], isNotEmpty);
      expect(res['circle_id'], isNotEmpty);
    });

    test('circle members come back', () async {
      final res = await ApiClient.getCircleMembers(
          '6829dad5-2e30-4adf-911b-0c91e254013f');
      expect(res, isNotEmpty);
    });

    // The bypass is currently ON in production (ENVIRONMENT=development on
    // Vercel). If you turn it off, this flips to expecting DevBypassUnavailable.
    test('dev bypass lists accounts', () async {
      final users = await ApiClient.devUsers();
      expect(users, isNotEmpty);
      expect(users.first, contains('email'));
    });

    test('dev login works with a name alone', () async {
      final res = await ApiClient.devLogin(name: 'Maya Chen');
      expect(res['name'], 'Maya Chen');
      expect(res['access_token'], isNotEmpty);
    });
  }, skip: 'live network test, run with --run-skipped');
}
