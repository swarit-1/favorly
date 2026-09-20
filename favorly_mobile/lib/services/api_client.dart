import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Where requests go. Set it at runtime from the app's Server field, or at
/// build time with `--dart-define=API_BASE_URL=https://your-host`.
String get apiBaseUrl => ApiConfig.baseUrl;

/// A connection failure says which URL it tried: "SocketException" on its own
/// sends you hunting. On a physical device the default `localhost` is the
/// phone, not your Mac; pass `--dart-define=API_BASE_URL=http://<mac-ip>:8000`.
Never _unreachable(Object error) {
  throw Exception(
    "Can't reach the API at $apiBaseUrl.\n"
    'Is the backend running, and is this the right host for this device?\n'
    '($error)',
  );
}

/// The server has `/auth/dev/*` switched off, so it isn't running with
/// ENVIRONMENT=development. Expected against the deployed API, where the
/// bypass is deliberately disabled so a public URL can't log in as anyone.
class DevBypassUnavailable implements Exception {
  DevBypassUnavailable(this.baseUrl);

  final String baseUrl;

  @override
  String toString() =>
      'The dev bypass is off on $baseUrl. Sign in with an email and password.';
}

/// Decode a response body that is supposed to be JSON.
///
/// Vercel's deployment-specific URLs (the ones the CLI prints) sit behind SSO
/// and answer with a 200 HTML login page, so a wrong-but-plausible base URL
/// fails as an unreadable FormatException. Name the problem instead.
dynamic _decodeJson(http.Response response, String what) {
  final type = response.headers['content-type'] ?? '';
  if (!type.contains('json')) {
    throw Exception(
      '$what: $apiBaseUrl returned ${response.statusCode} $type, not JSON.\n'
      'If that is a Vercel deployment URL it is SSO-protected, so use the '
      'project alias instead.',
    );
  }
  return jsonDecode(response.body);
}

class ApiClient {
  static Future<Map<String, dynamic>> signup({
    required String name,
    required String email,
    required String password,
    required String inviteCode,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'invite_code': inviteCode,
      }),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Signup failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Login') as Map<String, dynamic>;
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  // --- DEV BYPASS: seeded Supabase Auth accounts, no password needed. ---

  /// Everyone with a seeded auth account you can dev-log-in as.
  static Future<List<Map<String, dynamic>>> devUsers() async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/auth/dev/users'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(
          _decodeJson(response, 'Dev users') as List);
    } else if (response.statusCode == 404) {
      throw DevBypassUnavailable(apiBaseUrl);
    } else {
      throw Exception('Dev users failed: ${response.body}');
    }
  }

  /// Log in as whoever matches [name]: an email, an exact name, else a substring.
  /// Returns a real Supabase JWT.
  static Future<Map<String, dynamic>> devLogin({required String name}) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/auth/dev/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Dev login') as Map<String, dynamic>;
    } else if (response.statusCode == 404) {
      throw DevBypassUnavailable(apiBaseUrl);
    } else {
      throw Exception('Dev login failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> createTrip({
    required String store,
    required DateTime departAt,
    required String userId,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/trips'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'User-$userId',
      },
      body: jsonEncode({
        'store': store,
        'depart_at': departAt.toIso8601String(),
        'caps': {
          'max_requesters': 6,
          'max_dollars_per_person': '40.00',
          'max_items_per_person': 8,
        },
      }),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Create trip failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getTrip(String tripId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/trips/$tripId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Get trip failed: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> listTrips(String circleId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/trips/circle/$circleId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('List trips failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> createRequest({
    required String tripId,
    required List<Map<String, dynamic>> items,
    required String userId,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/requests/$tripId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'User-$userId',
      },
      body: jsonEncode({
        'items': items,
      }),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Create request failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getRequest(String requestId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/requests/$requestId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Get request failed: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> listRequests(String tripId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/requests/trip/$tripId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('List requests failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> updateRequestStatus({
    required String requestId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/requests/$requestId/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Update request status failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getMergedList(String tripId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/trips/$tripId/merged-list'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Get merged list failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getUser(String userId) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/users/$userId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Get user failed: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getCircleMembers(
    String circleId,
  ) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/users/circle/$circleId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Get circle members failed: ${response.body}');
    }
  }
}
