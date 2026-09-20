import 'dart:convert';
import 'package:http/http.dart' as http;

import '../dev/fixtures.dart';
import '../models/route_models.dart';
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

  // --- FAVORLY ROUTE (S2) ---

  /// The shortest walk through the store for [tripId], plus explained
  /// suggestions and per-requester cap totals. Accepting a suggestion is a
  /// re-call with its item appended to [extraItems]
  /// (`{"name","qty","section"}` maps, `requester_id` optional).
  static Future<RoutePlan> planRoute(
    String tripId, {
    List<Map<String, dynamic>>? extraItems,
  }) async {
    if (kUseFixtures) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return RoutePlan.fromJson(
        fixtureRoutePlan(tripId, extraItems ?? const []),
      );
    }
    final body = <String, dynamic>{'trip_id': tripId};
    if (extraItems != null && extraItems.isNotEmpty) {
      body['extra_items'] = extraItems;
    }
    final response = await http.post(
      Uri.parse('$apiBaseUrl/route/plan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return RoutePlan.fromJson(
        _decodeJson(response, 'Plan route') as Map<String, dynamic>,
      );
    } else {
      throw Exception('Plan route failed: ${response.body}');
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

  static Future<Map<String, dynamic>> updateProfile({
    required String userId,
    required String accessToken,
    String? bio,
    String? photoUrl,
    String? role,
    Map<String, String?>? address,
    List<String>? dietary,
    List<String>? preferredStores,
    List<String>? availability,
  }) async {
    final body = <String, dynamic>{};
    if (bio != null) body['bio'] = bio;
    if (photoUrl != null) body['photo_url'] = photoUrl;
    if (role != null) body['role'] = role;
    if (address != null) body['address'] = address;
    if (dietary != null) body['dietary'] = dietary;
    if (preferredStores != null) body['preferred_stores'] = preferredStores;
    if (availability != null) body['availability'] = availability;

    final response = await http.patch(
      Uri.parse('$apiBaseUrl/users/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Update profile failed: ${response.body}');
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

  // --- EXPERIENCE RATINGS ---

  static Future<Map<String, dynamic>> submitExperienceRating({
    required String tripId,
    required String circleId,
    required String ratedById,
    required String ratedId,
    required int overallRating,
    int? reliabilityRating,
    int? accuracyRating,
    int? communicationRating,
    String? comment,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/experiences'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'trip_id': tripId,
        'circle_id': circleId,
        'rated_by_id': ratedById,
        'rated_id': ratedId,
        'overall_rating': overallRating,
        'reliability_rating': reliabilityRating,
        'accuracy_rating': accuracyRating,
        'communication_rating': communicationRating,
        'comment': comment,
      }),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Submit experience rating failed: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getExperiences({
    String? ratedId,
    String? ratedById,
    String? tripId,
  }) async {
    final params = <String, String>{};
    if (ratedId != null) params['rated_id'] = ratedId;
    if (ratedById != null) params['rated_by_id'] = ratedById;
    if (tripId != null) params['trip_id'] = tripId;

    final uri = Uri.parse('$apiBaseUrl/experiences')
        .replace(queryParameters: params.isNotEmpty ? params : null);

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Get experiences failed: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getMemberRecommendations({
    required String memberId,
    required String circleId,
    int limit = 3,
  }) async {
    final response = await http.get(
      Uri.parse(
        '$apiBaseUrl/experiences/members/$memberId/recommendations?circle_id=$circleId&limit=$limit',
      ),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Get member recommendations failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> refreshCompatibilityCache({
    String? circleId,
  }) async {
    final body = circleId != null ? jsonEncode({'circle_id': circleId}) : null;

    final response = await http.post(
      Uri.parse('$apiBaseUrl/experiences/refresh-compatibility'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Refresh compatibility cache failed: ${response.body}');
    }
  }

  // --- MESSAGES (Live Chat) ---

  static Future<Map<String, dynamic>> postMessage({
    required String tripId,
    required String body,
    required String accessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/messages/$tripId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'body': body}),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Post message failed: ${response.body}');
    }
  }

  static Future<List<Map<String, dynamic>>> getMessages({
    required String tripId,
    int limit = 50,
    String? before,
  }) async {
    final params = <String, String>{'limit': limit.toString()};
    if (before != null) params['before'] = before;

    final uri = Uri.parse('$apiBaseUrl/messages/$tripId')
        .replace(queryParameters: params);

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Get messages failed: ${response.body}');
    }
  }

  // --- NOTIFICATIONS ---

  static Future<List<Map<String, dynamic>>> getNotifications({
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/notifications'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Get notifications failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> markNotificationRead({
    required String notificationId,
    required String accessToken,
  }) async {
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/notifications/$notificationId/read'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Mark notification read failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> markAllNotificationsRead({
    required String accessToken,
  }) async {
    final response = await http.patch(
      Uri.parse('$apiBaseUrl/notifications/read-all'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Mark all notifications read failed: ${response.body}');
    }
  }

  // --- SAVINGS METER ---

  static Future<Map<String, dynamic>> getSavings({
    required String userId,
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/savings/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Get savings') as Map<String, dynamic>;
    } else {
      throw Exception('Get savings failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getInsuranceStatus({
    required String userId,
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/insurance/status/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Get insurance status') as Map<String, dynamic>;
    } else {
      throw Exception('Get insurance status failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> checkInsuranceEligible({
    required String userId,
    required String accessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/insurance/check-eligible/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Check insurance eligible') as Map<String, dynamic>;
    } else {
      throw Exception('Check insurance eligible failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getUnlockStatus({
    required String circleId,
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/unlocks/status/$circleId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Get unlock status') as Map<String, dynamic>;
    } else {
      throw Exception('Get unlock status failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> claimUnlock({
    required String circleId,
    required String unlockType,
    required String accessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/unlocks/claim/$circleId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'unlock_type': unlockType}),
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Claim unlock') as Map<String, dynamic>;
    } else {
      throw Exception('Claim unlock failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> getReferralStats({
    required String userId,
    required String accessToken,
  }) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl/referrals/stats/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Get referral stats') as Map<String, dynamic>;
    } else {
      throw Exception('Get referral stats failed: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> checkNewReferralRewards({
    required String userId,
    required String accessToken,
  }) async {
    final response = await http.post(
      Uri.parse('$apiBaseUrl/referrals/check-earned/$userId'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return _decodeJson(response, 'Check referral rewards') as Map<String, dynamic>;
    } else {
      throw Exception('Check referral rewards failed: ${response.body}');
    }
  }
}
