// Exercises the real agent service through the app's own client. Skipped by
// default because it hits the network:
//
//   flutter test test/live_trellis_test.dart --run-skipped
//
// Runs against the deployed service; point TRELLIS at a local one to debug.

import 'package:flutter_test/flutter_test.dart';

import 'package:favorly_mobile/services/api_config.dart';
import 'package:favorly_mobile/services/trellis_client.dart';

const _sam = 'bd799ddc-61c6-456e-ab2c-00f1725e149c'; // Sam Okonkwo
const _jordan = 'acd2ee77-4d8f-4ade-b9a4-0eb2449e507b'; // Jordan Reyes

void main() {
  group(
    'live agent service',
    () {
      setUpAll(() async {
        TestWidgetsFlutterBinding.ensureInitialized();
        await ApiConfig.setTrellis(ApiConfig.trellisCompiledDefault);
      });

      test('recommendations parse into FavorSuggestion', () async {
        final favors = await TrellisClient.recommendations(_sam, limit: 3);
        expect(favors, isNotEmpty);

        final f = favors.first;
        expect(f.needId, isNotEmpty);
        expect(f.title, isNotEmpty);
        expect(f.requesterName, isNotEmpty);
        expect(f.originalRequest, isNotEmpty);
        expect(f.reason, isNotEmpty);
        expect(f.score, greaterThan(0));
        expect(f.signals.keys, contains('trip'));
        // FastAPI emits ints for whole numbers; these must still be doubles.
        for (final v in f.signals.values) {
          expect(v, isA<double>());
        }
      });

      test('claimed-by set comes back', () async {
        final started = await TrellisClient.needIdsClaimedBy(_sam);
        expect(started, isA<Set<String>>());
      });

      test('a favor round-trips: claim, fulfill, review', () async {
        // Jordan posts something so we have a fresh need to act on.
        final favors = await TrellisClient.recommendations(_sam, limit: 10);
        final target = favors.firstWhere(
          (f) => f.requesterId != _sam,
          orElse: () =>
              throw StateError('no actionable favor in recommendations'),
        );

        await TrellisClient.claim(needId: target.needId, personId: _sam);
        expect(
          await TrellisClient.needIdsClaimedBy(_sam),
          contains(target.needId),
        );

        await TrellisClient.fulfill(needId: target.needId);
        await TrellisClient.review(
          needId: target.needId,
          reviewerId: _sam,
          rating: 4,
          comment: 'went fine, store was busy',
        );
      });

      test(
        'claiming an already-claimed favor raises TrellisConflict',
        () async {
          final favors = await TrellisClient.recommendations(
            _jordan,
            limit: 10,
          );
          final target = favors.firstWhere(
            (f) => f.requesterId != _jordan,
            orElse: () => throw StateError('no actionable favor'),
          );

          await TrellisClient.claim(needId: target.needId, personId: _jordan);
          await expectLater(
            TrellisClient.claim(needId: target.needId, personId: _sam),
            throwsA(isA<TrellisConflict>()),
          );
        },
      );
    },
    skip: 'live network test — run with --run-skipped against a local agent service',
  );
}
