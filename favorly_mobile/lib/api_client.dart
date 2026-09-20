import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

/// Thin REST client for the FastAPI backend (backend/app.py). Deliberately
/// not using supabase_flutter for these calls -- the backend is where trip
/// completion forwards a real favor to the Trellis agent + graph service
/// (services/trellis_client.py), so writes need to go through it, not
/// straight to Supabase.
class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _base = AppConfig.apiBaseUrl;

  Map<String, String> get _headers => const {'Content-Type': 'application/json'};

  dynamic _decode(http.Response resp) {
    if (resp.statusCode >= 400) {
      throw ApiException(resp.statusCode, resp.body);
    }
    if (resp.body.isEmpty) return null;
    return jsonDecode(resp.body);
  }

  Future<List<Trip>> fetchCircleTrips(String circleId) async {
    final resp = await _client.get(Uri.parse('$_base/circles/$circleId/trips'));
    final data = _decode(resp) as Map<String, dynamic>;
    return (data['trips'] as List)
        .map((t) => Trip.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<Trip> createTrip({
    required String shopperId,
    required String circleId,
    required String store,
    required DateTime departAt,
  }) async {
    final resp = await _client.post(
      Uri.parse('$_base/trips'),
      headers: _headers,
      body: jsonEncode({
        'shopper_id': shopperId,
        'circle_id': circleId,
        'store': store,
        'depart_at': departAt.toUtc().toIso8601String(),
      }),
    );
    return Trip.fromJson(_decode(resp) as Map<String, dynamic>);
  }

  Future<String> attachRequest({
    required String tripId,
    required String requesterId,
    required List<Map<String, dynamic>> items,
  }) async {
    final resp = await _client.post(
      Uri.parse('$_base/trips/$tripId/requests'),
      headers: _headers,
      body: jsonEncode({'requester_id': requesterId, 'items': items}),
    );
    final data = _decode(resp) as Map<String, dynamic>;
    return data['request_id'] as String;
  }

  Future<void> acceptRequest(String requestId) async {
    final resp = await _client.patch(
      Uri.parse('$_base/requests/$requestId'),
      headers: _headers,
      body: jsonEncode({'status': 'accepted'}),
    );
    _decode(resp);
  }

  /// Marks the trip done and forwards one favor per accepted requester to
  /// Trellis -- see backend/app.py's handoff_trip and services/trellis_client.py.
  Future<int> handoffTrip(String tripId) async {
    final resp = await _client.post(Uri.parse('$_base/trips/$tripId/handoff'));
    final data = _decode(resp) as Map<String, dynamic>;
    return data['favors_logged'] as int;
  }

  Future<List<LedgerRow>> fetchLedger(String circleId) async {
    final resp = await _client.get(Uri.parse('$_base/circles/$circleId/ledger'));
    final data = _decode(resp) as Map<String, dynamic>;
    return (data['rows'] as List)
        .map((r) => LedgerRow.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
