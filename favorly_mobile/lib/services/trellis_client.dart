import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Where the agent + graph service lives. Separate deployment from the errand
/// API, so it has its own base URL. Set it at runtime from the Server field,
/// or at build time with `--dart-define=TRELLIS_BASE_URL=https://your-host`.
String get trellisBaseUrl => ApiConfig.trellisBaseUrl;

/// A connection failure says which URL it tried: "SocketException" on its own
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

/// The need moved on before this request landed: someone else claimed it, or
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

/// The structured facts behind a recommendation, the same ones the server
/// turned into the prose `reason`, kept apart so they can be drawn rather
/// than parsed back out of a sentence.
///
/// None of this is model-written. The model only ever phrases [FavorSuggestion.reason];
/// everything here came off the graph.
class MatchEvidence {
  const MatchEvidence({
    this.weights = const {},
    this.mutualNames = const [],
    this.favorCount = 0,
    this.tripReason,
    this.fitReason,
    this.affinityReason,
    this.graphReason,
  });

  /// How much each signal counts toward the score, straight from the server's
  /// WEIGHTS. Sent rather than hardcoded so a retune can't leave the UI
  /// quietly explaining the old arithmetic.
  final Map<String, double> weights;

  final List<String> mutualNames;

  /// Favors they have done *for you*. The direction matters: this is the
  /// reciprocity signal, and inverting it is the one error that would matter.
  final int favorCount;

  final String? tripReason;
  final String? fitReason;
  final String? affinityReason;

  /// The sentence the deterministic ranking would have written on its own.
  /// When the model phrased the reason, this is what it replaced.
  final String? graphReason;

  static const empty = MatchEvidence();

  bool get isEmpty =>
      mutualNames.isEmpty &&
      favorCount == 0 &&
      tripReason == null &&
      fitReason == null &&
      affinityReason == null;

  /// What this signal contributed to the final score: its weight times how
  /// strongly it fired. Falls back to the raw value when the server sent no
  /// weight for it, so an unknown signal still draws something truthful.
  double contribution(String signal, double value) =>
      (weights[signal] ?? 1.0) * value;

  static String? _orNull(dynamic v) {
    final s = v == null ? '' : '$v';
    return s.isEmpty || s == 'null' ? null : s;
  }

  factory MatchEvidence.fromJson(Map<String, dynamic> json) {
    final rawWeights = json['weights'];
    final weights = <String, double>{};
    if (rawWeights is Map) {
      rawWeights.forEach((k, v) => weights['$k'] = _asDouble(v));
    }
    final mutuals = json['mutual_names'];
    return MatchEvidence(
      weights: weights,
      mutualNames: mutuals is List
          ? mutuals.map((m) => '$m').where((m) => m.isNotEmpty).toList()
          : const [],
      favorCount: (json['favor_count'] as num?)?.toInt() ?? 0,
      tripReason: _orNull(json['trip_reason']),
      fitReason: _orNull(json['fit_reason']),
      affinityReason: _orNull(json['affinity_reason']),
      graphReason: _orNull(json['graph_reason']),
    );
  }

  Map<String, dynamic> toJson() => {
        'weights': Map<String, double>.from(weights),
        'mutual_names': mutualNames,
        'favor_count': favorCount,
        'trip_reason': tripReason,
        'fit_reason': fitReason,
        'affinity_reason': affinityReason,
        'graph_reason': graphReason,
      };
}

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

  /// "low" | "medium" | "high", kept as a string: the server owns the vocabulary.
  final String effort;
  final double score;

  /// trip / reciprocity / mutual / fit / freshness, each roughly 0..1.
  final Map<String, double> signals;

  /// Already humanised by the server, e.g. "2h ago".
  final String posted;

  /// The graph facts the reason was built from. Empty for a favor that never
  /// arrived as a recommendation, see [ClaimedFavor.toSuggestion].
  final MatchEvidence why;

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
    this.why = MatchEvidence.empty,
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
      why: json['why'] is Map
          ? MatchEvidence.fromJson(Map<String, dynamic>.from(json['why'] as Map))
          : MatchEvidence.empty,
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
        'why': why.toJson(),
      };
}

/// A need this person has claimed, as `GET /needs?status=claimed` returns it.
///
/// Thinner than a [FavorSuggestion]: the graph's reasoning lives with the
/// recommendation, and a claimed need has already left the recommendation
/// list. Enough to say who you are helping and with what.
class ClaimedFavor {
  const ClaimedFavor({
    required this.needId,
    required this.body,
    required this.requesterId,
    required this.requesterName,
    this.createdAt,
  });

  final String needId;
  final String body;
  final String requesterId;
  final String requesterName;
  final DateTime? createdAt;

  factory ClaimedFavor.fromJson(Map<String, dynamic> json) {
    final postedBy = json['posted_by'];
    final poster = postedBy is Map
        ? Map<String, dynamic>.from(postedBy)
        : const <String, dynamic>{};
    return ClaimedFavor(
      needId: '${json['id'] ?? ''}',
      body: '${json['body'] ?? ''}',
      requesterId: '${poster['id'] ?? ''}',
      requesterName: '${poster['display_name'] ?? ''}',
      createdAt: DateTime.tryParse('${json['created_at']}'),
    );
  }

  /// The favor as the UI draws it, for the case where no richer copy of the
  /// recommendation survived. Their words stand in for a title the model would
  /// otherwise have written, and [FavorSuggestion.effort] is left empty so the
  /// UI knows not to draw an effort it never heard.
  FavorSuggestion toSuggestion({String? posted}) => FavorSuggestion(
        needId: needId,
        title: body,
        action: '',
        requesterId: requesterId,
        requesterName: requesterName,
        originalRequest: body,
        reason: '',
        effort: '',
        score: 0,
        signals: const {},
        posted: posted ?? '',
      );
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

  /// The favors [personId] is on the hook for right now: the claimed ones they
  /// claimed themselves, newest first. Fulfilled needs have left this list.
  ///
  /// Recommendations only ever return open needs, so once you take a favor on
  /// it drops out of that list. This is how the app finds it again after a
  /// restart, on a device that never saw the recommendation.
  static Future<List<ClaimedFavor>> claimedBy(String personId) async {
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/needs?status=claimed'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      final body = _decodeJson(response, 'Needs') as Map<String, dynamic>;
      final needs = body['needs'];
      if (needs is! List) return const [];
      final mine = needs
          .whereType<Map>()
          .map((n) => Map<String, dynamic>.from(n))
          .where((n) => '${n['claimed_by']}' == personId)
          .map(ClaimedFavor.fromJson)
          .toList();
      mine.sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        if (at == null || bt == null) return 0;
        return bt.compareTo(at);
      });
      return mine;
    } else {
      throw Exception('List needs failed: ${response.body}');
    }
  }

  /// The circle's favor network, as [personId] can see it.
  ///
  /// Scoped to their circle server-side: passing no person returns every
  /// account in the database, which is never what a member should be shown.
  static Future<FavorGraph> graph(String personId) async {
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/graph?person_id=$personId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      final body = _decodeJson(response, 'Graph') as Map<String, dynamic>;
      final nodes = body['nodes'], edges = body['edges'];
      return FavorGraph(
        nodes: nodes is List
            ? nodes
                .whereType<Map>()
                .map((n) => GraphNode.fromJson(Map<String, dynamic>.from(n)))
                .toList()
            : const [],
        edges: edges is List
            ? edges
                .whereType<Map>()
                .map((e) => GraphEdge.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );
    } else if (response.statusCode == 409) {
      // Not in a circle yet. An empty map is the honest answer, not an error.
      return FavorGraph.empty;
    } else {
      throw Exception(
          'Graph failed: $trellisBaseUrl returned ${response.statusCode}. '
          '${response.body}');
    }
  }

  /// What ties [personId] to [otherId]. Direction is preserved: the result's
  /// `given` is favors [personId] did, `received` is favors they got.
  static Future<FavorThread> thread({
    required String personId,
    required String otherId,
  }) async {
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/graph/thread/$personId/$otherId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 200) {
      return FavorThread.fromJson(
          _decodeJson(response, 'Thread') as Map<String, dynamic>);
    } else {
      throw Exception('Thread failed: ${response.body}');
    }
  }
}

/// One neighbor as the favor map draws them.
///
/// [degree] and [cluster] are computed server-side over the scoped graph, so
/// they already mean "within this circle" rather than "within the database".
class GraphNode {
  const GraphNode({
    required this.id,
    required this.name,
    required this.degree,
    required this.cluster,
  });

  final String id;
  final String name;

  /// How many distinct neighbors this person has exchanged anything with.
  final int degree;

  /// Community index from the server's modularity pass. -1 when unassigned.
  final int cluster;

  factory GraphNode.fromJson(Map<String, dynamic> json) => GraphNode(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        degree: (json['degree'] as num?)?.toInt() ?? 0,
        cluster: (json['cluster'] as num?)?.toInt() ?? -1,
      );
}

/// A tie between two neighbors. [strength] is time-decayed, so an old favor
/// draws thinner than a recent one without either ever being deleted.
class GraphEdge {
  const GraphEdge({
    required this.src,
    required this.dst,
    required this.kind,
    required this.strength,
  });

  final String src;
  final String dst;

  /// "favor" | "co_occurrence". The server owns the vocabulary.
  final String kind;
  final double strength;

  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(
        src: '${json['src'] ?? ''}',
        dst: '${json['dst'] ?? ''}',
        kind: '${json['kind'] ?? ''}',
        strength: _asDouble(json['strength']),
      );
}

/// The circle's favor network: who is tied to whom, and how strongly.
class FavorGraph {
  const FavorGraph({required this.nodes, required this.edges});

  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  static const empty = FavorGraph(nodes: [], edges: []);

  bool get isEmpty => nodes.isEmpty;

  /// Distinct clusters present, so a legend only lists communities that exist.
  int get clusterCount =>
      nodes.map((n) => n.cluster).where((c) => c >= 0).toSet().length;
}

/// Favors in one direction between two people.
class ThreadDirection {
  const ThreadDirection({
    required this.count,
    required this.strength,
    this.lastAt,
  });

  final int count;
  final double strength;
  final DateTime? lastAt;

  static const none = ThreadDirection(count: 0, strength: 0);

  factory ThreadDirection.fromJson(Map<String, dynamic> json) => ThreadDirection(
        count: (json['count'] as num?)?.toInt() ?? 0,
        strength: _asDouble(json['strength']),
        lastAt: DateTime.tryParse('${json['last_at']}'),
      );
}

/// Something both people said about themselves, as extraction recorded it.
class SharedClaim {
  const SharedClaim({required this.kind, required this.label});

  /// dietary | mobility | budget | preference.
  final String kind;
  final String label;

  factory SharedClaim.fromJson(Map<String, dynamic> json) {
    final canonical = '${json['canonical'] ?? ''}';
    final raw = '${json['raw_label'] ?? ''}';
    return SharedClaim(
      kind: '${json['kind'] ?? ''}',
      label: canonical.isNotEmpty ? canonical : raw,
    );
  }
}

/// Everything the graph holds about one pair of neighbors: the expanded view
/// behind tapping an edge on the map.
class FavorThread {
  const FavorThread({
    required this.otherId,
    required this.otherName,
    required this.given,
    required this.received,
    required this.mutuals,
    required this.sharedClaims,
    this.firstAt,
  });

  final String otherId;
  final String otherName;

  /// Favors *you* did for them, and they for you. Named from the point of
  /// view of whoever was passed as `a`, see [TrellisClient.thread].
  final ThreadDirection given;
  final ThreadDirection received;

  final List<String> mutuals;
  final List<SharedClaim> sharedClaims;
  final DateTime? firstAt;

  /// Have these two ever actually done anything for each other?
  bool get hasHistory => given.count > 0 || received.count > 0;

  /// Is there anything at all to show, history or structure?
  bool get isEmpty => !hasHistory && mutuals.isEmpty && sharedClaims.isEmpty;

  factory FavorThread.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic v) =>
        v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

    final b = asMap(json['b']);
    final favors = asMap(json['favors']);
    final mutuals = json['mutuals'];
    final shared = json['shared_claims'];

    return FavorThread(
      otherId: '${b['id'] ?? ''}',
      otherName: '${b['display_name'] ?? ''}',
      given: favors['a_to_b'] == null
          ? ThreadDirection.none
          : ThreadDirection.fromJson(asMap(favors['a_to_b'])),
      received: favors['b_to_a'] == null
          ? ThreadDirection.none
          : ThreadDirection.fromJson(asMap(favors['b_to_a'])),
      mutuals: mutuals is List
          ? mutuals
              .whereType<Map>()
              .map((m) => '${m['display_name'] ?? ''}')
              .where((n) => n.isNotEmpty)
              .toList()
          : const [],
      sharedClaims: shared is List
          ? shared
              .whereType<Map>()
              .map((s) => SharedClaim.fromJson(Map<String, dynamic>.from(s)))
              .toList()
          : const [],
      firstAt: DateTime.tryParse('${favors['first_at']}'),
    );
  }
}
