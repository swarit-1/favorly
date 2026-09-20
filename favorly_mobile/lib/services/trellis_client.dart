import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Where the agent + graph service lives. Separate deployment from the errand
/// API, so it has its own base URL — set it at runtime from the Server field,
/// or at build time with `--dart-define=TRELLIS_BASE_URL=https://your-host`.
String get trellisBaseUrl => ApiConfig.trellisBaseUrl;

/// A connection failure says which URL it tried — "SocketException" on its own
/// sends you hunting. Trellis defaults to `http://localhost:8010`, which on a
/// physical device is the phone, not your Mac; pass
/// `--dart-define=TRELLIS_BASE_URL=http://<mac-ip>:8010`.
Never _unreachable(Object error) {
  throw Exception(
    "Can't reach Trellis at $trellisBaseUrl.\n"
    'Is the agent service running, and is this the right host for this device?\n'
    '($error)',
  );
}

/// The need moved on before this request landed — someone else claimed it, or
/// it isn't in the state the action needs. Trellis answers 409 for all of them.
/// Worth its own type: the UI wants to refresh rather than show a raw error.
class TrellisConflict implements Exception {
  TrellisConflict(this.what, this.body);

  final String what;
  final String body;

  @override
  String toString() => '$what: that favor has already moved on. ($body)';
}

/// Decode a response body that is supposed to be JSON.
///
/// A wrong-but-plausible base URL (a tunnel that has since been handed to
/// something else, an SSO login page) answers 200 with HTML, which otherwise
/// fails as an unreadable FormatException. Name the problem instead.
dynamic _decodeJson(http.Response response, String what) {
  final type = response.headers['content-type'] ?? '';
  if (!type.contains('json')) {
    throw Exception(
      '$what: $trellisBaseUrl returned ${response.statusCode} $type, not JSON.\n'
      'Is that the Trellis service, or something else answering on that host?',
    );
  }
  return jsonDecode(response.body);
}

double _asDouble(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0.0;

/// One favor Trellis thinks you are well placed to do, with the reasoning it
/// used. Round-trips through [toJson] so the list can sit in shared_preferences.
class FavorSuggestion {
  final String needId;
  final String title;
  final String action;
  final String requesterId;
  final String requesterName;
  final String originalRequest;
  final String reason;

  /// "low" | "medium" | "high" — kept as a string, the server owns the vocabulary.
  final String effort;
  final double score;

  /// trip / reciprocity / mutual / fit / freshness, each roughly 0..1.
  final Map<String, double> signals;

  /// Already humanised by the server, e.g. "2h ago".
  final String posted;

  const FavorSuggestion({
    required this.needId,
    required this.title,
    required this.action,
    required this.requesterId,
    required this.requesterName,
    required this.originalRequest,
    required this.reason,
    required this.effort,
    required this.score,
    required this.signals,
    required this.posted,
  });

  factory FavorSuggestion.fromJson(Map<String, dynamic> json) {
    final requestedBy = json['requested_by'];
    final requester = requestedBy is Map
        ? Map<String, dynamic>.from(requestedBy)
        : const <String, dynamic>{};
    final rawSignals = json['signals'];
    final signals = <String, double>{};
    if (rawSignals is Map) {
      rawSignals.forEach((key, value) => signals['$key'] = _asDouble(value));
    }

    return FavorSuggestion(
      needId: '${json['need_id'] ?? ''}',
      title: '${json['title'] ?? ''}',
      action: '${json['action'] ?? ''}',
      requesterId: '${requester['id'] ?? ''}',
      requesterName: '${requester['display_name'] ?? ''}',
      originalRequest: '${json['original_request'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      effort: '${json['effort'] ?? ''}',
      score: _asDouble(json['score']),
      signals: signals,
      posted: '${json['posted'] ?? ''}',
    );
  }

  /// The same shape the server sends, so a cached list decodes with [fromJson].
  Map<String, dynamic> toJson() => {
        'need_id': needId,
        'title': title,
        'action': action,
        'requested_by': {'id': requesterId, 'display_name': requesterName},
        'original_request': originalRequest,
        'reason': reason,
        'effort': effort,
        'score': score,
        'signals': Map<String, double>.from(signals),
        'posted': posted,
      };
}

class TrellisClient {
  /// The favors Trellis recommends [personId] pick up, best first.
  static Future<List<FavorSuggestion>> recommendations(
    String personId, {
    int limit = 10,
  }) async {
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/people/$personId/recommendations?limit=$limit'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      final body = _decodeJson(response, 'Recommendations') as Map<String, dynamic>;
      final favors = body['favors'];
      if (favors is! List) return const [];
      return favors
          .whereType<Map>()
          .map((f) => FavorSuggestion.fromJson(Map<String, dynamic>.from(f)))
          .toList();
    } else {
      throw Exception(
          'Recommendations failed: $trellisBaseUrl returned '
          '${response.statusCode}. ${response.body}');
    }
  }

  /// Take the favor on. 409 when someone else already claimed it.
  static Future<void> claim({
    required String needId,
    required String personId,
  }) async {
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/claim'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'person_id': personId}),
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Claim', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Claim failed: ${response.body}');
    }
  }

  /// Mark it done. 409 unless the need is currently claimed.
  static Future<void> fulfill({required String needId}) async {
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/fulfill'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Fulfill', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Fulfill failed: ${response.body}');
    }
  }

  /// Rate a finished favor. 409 unless the need is fulfilled.
  static Future<void> review({
    required String needId,
    required String reviewerId,
    required int rating,
    String? comment,
  }) async {
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/review'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'reviewer_id': reviewerId,
        'rating': rating,
        'comment': comment,
      }),
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Review', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Review failed: ${response.body}');
    }
  }

  /// Which needs [personId] is currently on the hook for — the claimed ones
  /// they claimed themselves. Fulfilled needs have left this set.
  static Future<Set<String>> needIdsClaimedBy(String personId) async {
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/needs?status=claimed'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      final body = _decodeJson(response, 'Needs') as Map<String, dynamic>;
      final needs = body['needs'];
      if (needs is! List) return <String>{};
      return needs
          .whereType<Map>()
          .where((n) => '${n['claimed_by']}' == personId)
          .map((n) => '${n['id']}')
          .toSet();
    } else {
      throw Exception('List needs failed: ${response.body}');
    }
  }
}
