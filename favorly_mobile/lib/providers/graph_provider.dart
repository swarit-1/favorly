import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/trellis_client.dart';

/// The circle's favor map, as this person can see it.
///
/// Scoped by person because the server scopes it: degree and community are
/// computed within the circle, so one person's map is not another's with the
/// names changed.
final favorGraphProvider =
    FutureProvider.family<FavorGraph, String>((ref, personId) async {
  return TrellisClient.graph(personId);
});

/// The degrees-apart numbers under the web. Refreshed (invalidated) when a
/// favor of yours is fulfilled, which is the one moment they change on stage.
final graphStatsProvider =
    FutureProvider.family<GraphStats, String>((ref, personId) async {
  return TrellisClient.graphStats(personId);
});

/// One pair of neighbors, expanded. Keyed by both ids because direction
/// matters: `given` means favors the *first* id did.
final favorThreadProvider =
    FutureProvider.family<FavorThread, ({String meId, String otherId})>(
        (ref, key) async {
  return TrellisClient.thread(personId: key.meId, otherId: key.otherId);
});
