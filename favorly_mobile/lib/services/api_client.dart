import 'dart:convert';
import 'package:http/http.dart' as http;

const String apiBaseUrl = 'http://localhost:8000';

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
    );

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
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Login failed: ${response.body}');
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
    );

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
    );

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
    );

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
    );

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
    );

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
    );

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
    );

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
    );

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
    );

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
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Get circle members failed: ${response.body}');
    }
  }
}
