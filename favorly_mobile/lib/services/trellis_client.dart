import 'dart:convert';
import 'package:http/http.dart' as http;

import '../dev/fixtures.dart';
import '../models/favor_category.dart';
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
    this.forwardReason,
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

  /// Pay it forward: you did a favor for someone who is tied to the asker
  /// ("Nora, who you recently helped out, knows Priya"). Direction matters
  /// here as much as it does for [favorCount]: you helped the person in the
  /// middle, not the person asking.
  final String? forwardReason;

  /// The sentence the deterministic ranking would have written on its own.
  /// When the model phrased the reason, this is what it replaced.
  final String? graphReason;

  static const empty = MatchEvidence();

  bool get isEmpty =>
      mutualNames.isEmpty &&
      favorCount == 0 &&
      tripReason == null &&
      fitReason == null &&
      affinityReason == null &&
      forwardReason == null;

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
      forwardReason: _orNull(json['forward_reason']),
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
        'forward_reason': forwardReason,
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

  /// v2, all default-safe so a pre-v2 cache still decodes: what kind of favor
  /// this is (missing decodes as errand), when they need it in their words,
  /// and whether they asked *you* specifically. Invited favors sort first
  /// server-side; the app pins them with an "Asked for you" eyebrow.
  final FavorCategory category;
  final String whenText;
  final bool invited;

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
    this.category = FavorCategory.errand,
    this.whenText = '',
    this.invited = false,
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
      // v2 fields; a pre-v2 map simply has none of them.
      category: FavorCategory.fromWire(json['category']),
      whenText: '${json['when_text'] ?? ''}',
      invited: json['invited'] == true,
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
        'category': category.wire,
        'when_text': whenText,
        'invited': invited,
      };
}

/// One stop on the social path between you and a helper: You · Nora · Marcus.
class PathPerson {
  const PathPerson({required this.id, required this.name});

  final String id;
  final String name;

  factory PathPerson.fromJson(Map<String, dynamic> json) =>
      PathPerson(id: '${json['id'] ?? ''}', name: '${json['name'] ?? ''}');

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// One person Trellis picked to help with your ask, and the true, specific,
/// human reason why. Never a score: the ranking argument stays on the server.
class HelperMatch {
  const HelperMatch({
    required this.personId,
    required this.displayName,
    required this.firstName,
    required this.rank,
    required this.tie,
    required this.tieLabel,
    required this.hops,
    required this.path,
    required this.headline,
    required this.where,
    required this.reason,
    this.spark,
    this.signals = const {},
    this.why = const {},
    this.inviteStatus,
  });

  final String personId;
  final String displayName;
  final String firstName;
  final int rank;

  /// close | friend_of_friend | extended | new. The server owns the vocabulary.
  final String tie;
  final String tieLabel;
  final int hops;
  final List<PathPerson> path;
  final String headline;

  /// Relative pre-acceptance ("3 floors up"); the unit only after both sides
  /// said yes.
  final String where;
  final String reason;
  final String? spark;

  /// Raw ranking signals. Kept for the wire round trip, never rendered.
  final Map<String, dynamic> signals;
  final Map<String, dynamic> why;

  /// null | pending | accepted | declined.
  final String? inviteStatus;

  bool get isPending => inviteStatus == 'pending';
  bool get isAccepted => inviteStatus == 'accepted';
  bool get isDeclined => inviteStatus == 'declined';

  HelperMatch withInviteStatus(String? status) => HelperMatch(
        personId: personId,
        displayName: displayName,
        firstName: firstName,
        rank: rank,
        tie: tie,
        tieLabel: tieLabel,
        hops: hops,
        path: path,
        headline: headline,
        where: where,
        reason: reason,
        spark: spark,
        signals: signals,
        why: why,
        inviteStatus: status,
      );

  factory HelperMatch.fromJson(Map<String, dynamic> json) {
    // The live asks endpoint sends flat helper rows ({person_id, first_name,
    // rank, invite_status}) with no `person` map; tolerate both shapes.
    final person = json['person'] is Map
        ? Map<String, dynamic>.from(json['person'] as Map)
        : const <String, dynamic>{};
    final displayName =
        '${person['display_name'] ?? json['display_name'] ?? ''}';
    final rawFirst = '${person['first_name'] ?? json['first_name'] ?? ''}';
    final rawPath = json['path'];
    final spark = json['spark'];
    final status = json['invite_status'];
    return HelperMatch(
      personId: '${person['id'] ?? json['person_id'] ?? ''}',
      displayName: displayName,
      firstName: rawFirst.isNotEmpty
          ? rawFirst
          : displayName.trim().split(RegExp(r'\s+')).first,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      tie: '${json['tie'] ?? ''}',
      tieLabel: '${json['tie_label'] ?? ''}',
      hops: (json['hops'] as num?)?.toInt() ?? 1,
      path: rawPath is List
          ? rawPath
              .whereType<Map>()
              .map((p) => PathPerson.fromJson(Map<String, dynamic>.from(p)))
              .toList()
          : const [],
      headline: '${json['headline'] ?? ''}',
      where: '${json['where'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      spark: spark == null || '$spark'.isEmpty ? null : '$spark',
      signals: json['signals'] is Map
          ? Map<String, dynamic>.from(json['signals'] as Map)
          : const {},
      why: json['why'] is Map
          ? Map<String, dynamic>.from(json['why'] as Map)
          : const {},
      inviteStatus:
          status == null || '$status'.isEmpty ? null : '$status',
    );
  }
}

/// What intake parsed your ask into, when it was in scope.
class ParsedNeed {
  const ParsedNeed({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    this.requires = const [],
    this.whenText = '',
    this.durationMinutes,
    this.items = const [],
  });

  final String id;
  final FavorCategory category;
  final String title;
  final String body;
  final List<String> requires;
  final String whenText;
  final int? durationMinutes;

  /// Only for errands: the grocery-style items the list flow understands.
  final List<String> items;

  factory ParsedNeed.fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic v) =>
        v is List ? v.map((e) => '$e').where((s) => s.isNotEmpty).toList() : const [];
    return ParsedNeed(
      // The live asks endpoint flattens the need and names the id `need_id`.
      id: '${json['id'] ?? json['need_id'] ?? ''}',
      category: FavorCategory.fromWire(json['category']),
      title: '${json['title'] ?? ''}',
      body: '${json['body'] ?? ''}',
      requires: strings(json['requires']),
      whenText: '${json['when_text'] ?? ''}',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      items: strings(json['items']),
    );
  }
}

/// What POST /needs/intake made of the ask: parsed and created when in scope,
/// or the sentence and rewrite to bounce back with when it is not.
class IntakeResult {
  const IntakeResult({
    required this.intent,
    required this.scope,
    this.scopeReply,
    this.rightSized,
    this.need,
    this.parsedBy = '',
  });

  /// ask_favor | offer_help | not_a_favor.
  final String intent;

  /// ok | too_big | needs_pro | not_ok | unclear.
  final String scope;
  final String? scopeReply;
  final String? rightSized;
  final ParsedNeed? need;
  final String parsedBy;

  bool get isOk => scope == 'ok' && need != null;

  factory IntakeResult.fromJson(Map<String, dynamic> json) {
    String? orNull(dynamic v) =>
        v == null || '$v'.isEmpty || '$v' == 'null' ? null : '$v';
    return IntakeResult(
      intent: '${json['intent'] ?? ''}',
      scope: '${json['scope'] ?? ''}',
      scopeReply: orNull(json['scope_reply']),
      rightSized: orNull(json['right_sized']),
      need: json['need'] is Map
          ? ParsedNeed.fromJson(Map<String, dynamic>.from(json['need'] as Map))
          : null,
      parsedBy: '${json['parsed_by'] ?? ''}',
    );
  }
}

/// One need you posted, as GET /people/{id}/asks returns it: the need, where
/// it stands, everyone asked, and whoever said yes.
class MyAsk {
  const MyAsk({
    required this.need,
    required this.status,
    this.helpers = const [],
    this.accepted,
  });

  final ParsedNeed need;

  /// open | claimed | fulfilled. The server owns the vocabulary.
  final String status;
  final List<HelperMatch> helpers;
  final HelperMatch? accepted;

  /// Whoever the pending invite is with, if anyone.
  HelperMatch? get pending {
    for (final h in helpers) {
      if (h.isPending) return h;
    }
    return null;
  }

  bool get isFulfilled => status == 'fulfilled';

  factory MyAsk.fromJson(Map<String, dynamic> json) {
    final rawHelpers = json['helpers'];
    return MyAsk(
      need: json['need'] is Map
          ? ParsedNeed.fromJson(Map<String, dynamic>.from(json['need'] as Map))
          // PRD-DEVIATION: the asks contract is not pinned field-by-field in
          // the lane doc; tolerate a flattened row where the need's fields sit
          // at the top level.
          : ParsedNeed.fromJson(json),
      status: '${json['status'] ?? 'open'}',
      helpers: rawHelpers is List
          ? rawHelpers
              .whereType<Map>()
              .map((h) => HelperMatch.fromJson(Map<String, dynamic>.from(h)))
              .toList()
          : const [],
      // The live server names this `accepted_helper`.
      accepted: json['accepted'] is Map
          ? HelperMatch.fromJson(
              Map<String, dynamic>.from(json['accepted'] as Map))
          : json['accepted_helper'] is Map
              ? HelperMatch.fromJson(
                  Map<String, dynamic>.from(json['accepted_helper'] as Map))
              : null,
    );
  }
}

/// GET /graph/stats: the degrees-apart line under the web.
class GraphStats {
  const GraphStats({
    required this.people,
    required this.ties,
    required this.avgSeparation,
    required this.triangles,
  });

  final int people;
  final int ties;
  final double avgSeparation;
  final int triangles;

  factory GraphStats.fromJson(Map<String, dynamic> json) => GraphStats(
        people: (json['people'] as num?)?.toInt() ?? 0,
        ties: (json['ties'] as num?)?.toInt() ?? 0,
        avgSeparation: _asDouble(json['avg_separation']),
        triangles: (json['triangles'] as num?)?.toInt() ?? 0,
      );
}

/// What fulfilling a need did to the web, when the server says (both fields
/// are additive; an older server simply sends neither).
class FulfillResult {
  const FulfillResult({
    this.firstFavorTogether = false,
    this.separationBefore,
    this.separationAfter,
  });

  final bool firstFavorTogether;
  final double? separationBefore;
  final double? separationAfter;

  factory FulfillResult.fromJson(Map<String, dynamic> json) {
    final sep = json['separation'];
    final sepMap = sep is Map ? Map<String, dynamic>.from(sep) : null;
    return FulfillResult(
      firstFavorTogether: json['first_favor_together'] == true,
      separationBefore: sepMap == null ? null : _asDouble(sepMap['before']),
      separationAfter: sepMap == null ? null : _asDouble(sepMap['after']),
    );
  }
}

/// What answering an invite returned: the new status, and on a decline the
/// next best helper to slide into the vacated spot, when the server has one.
class InviteAnswer {
  const InviteAnswer({required this.status, this.next});

  final String status;
  final HelperMatch? next;

  factory InviteAnswer.fromJson(Map<String, dynamic> json) => InviteAnswer(
        status: '${json['status'] ?? ''}',
        next: json['next'] is Map
            ? HelperMatch.fromJson(
                Map<String, dynamic>.from(json['next'] as Map))
            : null,
      );
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
    if (kUseFixtures) {
      // PRD-DEVIATION: Appendix C has no recommendations fixture. One invited
      // row plus one plain row keeps the fixture home screen honest about
      // both looks (the pinned "Asked for you" and the ordinary card).
      await Future<void>.delayed(const Duration(milliseconds: 250));
      return [
        FavorSuggestion.fromJson({
          'need_id': 'need-fx-1',
          'title': 'Borrow a ladder for an hour',
          'action': 'Lend your ladder for about an hour today.',
          'requested_by': {'id': 'p-swarit', 'display_name': 'Swarit Rao'},
          'original_request': 'I need to borrow a ladder for an hour today',
          'reason': 'You have a 6 ft ladder, and you both know Nora.',
          'effort': 'low',
          'score': 0,
          'signals': {'capability': 1.0, 'tie': 0.6},
          'posted': 'just now',
          'category': 'borrow',
          'when_text': 'today',
          'invited': true,
        }),
        FavorSuggestion.fromJson({
          'need_id': 'need-fx-2',
          'title': 'Water two plants this weekend',
          'action': 'Water the plants on the windowsill, Saturday or Sunday.',
          'requested_by': {'id': 'p-nora', 'display_name': 'Nora Chen'},
          'original_request': 'away this weekend, can anyone water my plants?',
          'reason': 'Nora helped you carry groceries up last month.',
          'effort': 'low',
          'score': 0,
          'signals': {'reciprocity': 0.8, 'nearness': 0.7},
          'posted': '1h ago',
          'category': 'care',
          'when_text': 'this weekend',
        }),
      ];
    }
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
    if (kUseFixtures) return;
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
  ///
  /// The v2 response also says what the favor did to the web
  /// ([FulfillResult]); callers that only care that it worked can keep
  /// awaiting this as before.
  static Future<FulfillResult> fulfill({required String needId}) async {
    if (kUseFixtures) {
      return FulfillResult.fromJson(FixtureWorld.fulfill());
    }
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/fulfill'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Fulfill', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Fulfill failed: ${response.body}');
    }
    // The v1 service answered with nothing worth reading; only parse when the
    // body actually is JSON, so an older deployment cannot fail a fulfilled
    // favor after the fact.
    try {
      final body = _decodeJson(response, 'Fulfill');
      return body is Map
          ? FulfillResult.fromJson(Map<String, dynamic>.from(body))
          : const FulfillResult();
    } catch (_) {
      return const FulfillResult();
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
    if (kUseFixtures) return const [];
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
    if (kUseFixtures) {
      final g = FixtureWorld.graph(personId);
      return FavorGraph(
        nodes: (g['nodes'] as List)
            .whereType<Map>()
            .map((n) => GraphNode.fromJson(Map<String, dynamic>.from(n)))
            .toList(),
        edges: (g['edges'] as List)
            .whereType<Map>()
            .map((e) => GraphEdge.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
    }
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
    if (kUseFixtures) {
      // Just enough for the tap-a-node card to say something true.
      return FavorThread.fromJson({
        'b': {'id': otherId, 'display_name': ''},
        'favors': {},
        'mutuals': [
          {'display_name': 'Nora Chen'},
        ],
        'shared_claims': [],
      });
    }
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

  // -------------------------------------------------------------------------
  // v2: ask anything.
  // -------------------------------------------------------------------------

  /// POST /needs/intake: parse the ask, check it is neighbor-sized, and
  /// create the need when it is. [confirmRightSized] re-submits a rewrite the
  /// server previously offered and skips the scope check.
  static Future<IntakeResult> intake({
    required String personId,
    required String text,
    bool confirmRightSized = false,
    String source = 'app',
  }) async {
    if (kUseFixtures) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      return IntakeResult.fromJson(
          FixtureWorld.intake(text, confirmRightSized: confirmRightSized));
    }
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/intake'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'person_id': personId,
        'text': text,
        'confirm_right_sized': confirmRightSized,
        'source': source,
      }),
    ).catchError(_unreachable);

    if (response.statusCode != 200) {
      throw Exception('Intake failed: $trellisBaseUrl returned '
          '${response.statusCode}. ${response.body}');
    }
    return IntakeResult.fromJson(
        _decodeJson(response, 'Intake') as Map<String, dynamic>);
  }

  /// GET /needs/{id}/helpers: the ranked matches, three kinds of tie.
  static Future<List<HelperMatch>> helpers(
    String needId, {
    int limit = 3,
  }) async {
    if (kUseFixtures) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      final body = FixtureWorld.helpers();
      return (body['helpers'] as List)
          .whereType<Map>()
          .map((h) => HelperMatch.fromJson(Map<String, dynamic>.from(h)))
          .toList();
    }
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/needs/$needId/helpers?limit=$limit'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode != 200) {
      throw Exception('Helpers failed: $trellisBaseUrl returned '
          '${response.statusCode}. ${response.body}');
    }
    final body = _decodeJson(response, 'Helpers') as Map<String, dynamic>;
    final helpers = body['helpers'];
    if (helpers is! List) return const [];
    return helpers
        .whereType<Map>()
        .map((h) => HelperMatch.fromJson(Map<String, dynamic>.from(h)))
        .toList();
  }

  /// POST /needs/{id}/invite: ask one person. Idempotent per pair; 409 when
  /// the need is no longer open.
  static Future<String> invite({
    required String needId,
    required String helperId,
  }) async {
    if (kUseFixtures) {
      return '${FixtureWorld.invite(helperId)['status']}';
    }
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/invite'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'helper_id': helperId}),
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Invite', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Invite failed: ${response.body}');
    }
    final body = _decodeJson(response, 'Invite') as Map<String, dynamic>;
    return '${body['status'] ?? 'pending'}';
  }

  /// POST /needs/{id}/invites/{helper}/respond: yes or no. A decline may hand
  /// back the next best helper.
  static Future<InviteAnswer> respondInvite({
    required String needId,
    required String helperId,
    required bool accept,
  }) async {
    if (kUseFixtures) {
      return InviteAnswer.fromJson(
          FixtureWorld.respondInvite(helperId, accept: accept));
    }
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/invites/$helperId/respond'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'accept': accept}),
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Respond', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Respond failed: ${response.body}');
    }
    return InviteAnswer.fromJson(
        _decodeJson(response, 'Respond') as Map<String, dynamic>);
  }

  /// POST /needs/{id}/broadcast: ask everyone instead of one person.
  static Future<void> broadcast(String needId) async {
    if (kUseFixtures) {
      FixtureWorld.broadcast();
      return;
    }
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/broadcast'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Broadcast', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Broadcast failed: ${response.body}');
    }
  }

  /// POST /needs/{id}/cancel: take the ask down.
  static Future<void> cancelNeed(String needId) async {
    if (kUseFixtures) {
      FixtureWorld.cancel();
      return;
    }
    final response = await http.post(
      Uri.parse('$trellisBaseUrl/needs/$needId/cancel'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode == 409) {
      throw TrellisConflict('Cancel', response.body);
    } else if (response.statusCode != 200) {
      throw Exception('Cancel failed: ${response.body}');
    }
  }

  /// GET /people/{id}/asks: the needs I posted that are still moving, plus
  /// anything fulfilled in the last few minutes.
  static Future<List<MyAsk>> myAsks(String personId) async {
    if (kUseFixtures) {
      final body = FixtureWorld.myAsks();
      return (body['asks'] as List)
          .whereType<Map>()
          .map((a) => MyAsk.fromJson(Map<String, dynamic>.from(a)))
          .toList();
    }
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/people/$personId/asks'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode != 200) {
      throw Exception('Asks failed: $trellisBaseUrl returned '
          '${response.statusCode}. ${response.body}');
    }
    final body = _decodeJson(response, 'Asks') as Map<String, dynamic>;
    final asks = body['asks'];
    if (asks is! List) return const [];
    return asks
        .whereType<Map>()
        .map((a) => MyAsk.fromJson(Map<String, dynamic>.from(a)))
        .toList();
  }

  /// GET /graph/stats: the degrees-apart line.
  static Future<GraphStats> graphStats(String personId) async {
    if (kUseFixtures) {
      return GraphStats.fromJson(FixtureWorld.graphStats());
    }
    final response = await http.get(
      Uri.parse('$trellisBaseUrl/graph/stats?person_id=$personId'),
      headers: {'Content-Type': 'application/json'},
    ).catchError(_unreachable);

    if (response.statusCode != 200) {
      throw Exception('Graph stats failed: $trellisBaseUrl returned '
          '${response.statusCode}. ${response.body}');
    }
    return GraphStats.fromJson(
        _decodeJson(response, 'Graph stats') as Map<String, dynamic>);
  }

  /// GET /health, fire-and-forget: Trellis cold-starts slowly on Vercel, so
  /// the app pokes it on launch and never cares what comes back.
  static Future<void> warmup() async {
    if (kUseFixtures) return;
    try {
      await http.get(Uri.parse('$trellisBaseUrl/health'));
    } catch (_) {
      // Warmup is a nicety; a failure here says nothing the next real call
      // will not say better.
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
