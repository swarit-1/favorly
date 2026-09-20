import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/demo_cast.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

/// Post-trip survey screen: shopper rates each requester.
/// Appears after HandoffScreen → "Mark delivered" is confirmed.
class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  late Map<String, int> _ratings; // memberId -> overall_rating
  late Map<String, String> _comments; // memberId -> comment
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _ratings = {};
    _comments = {};
  }

  Future<void> _submitRatings() async {
    if (_ratings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rate at least one person to continue.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final store = ref.read(storeProvider);
      final trip = store.tripById(widget.tripId);

      // Submit each rating to the backend and demo store
      for (final entry in _ratings.entries) {
        final memberId = entry.key;
        final rating = entry.value;
        final comment = _comments[memberId];

        // Store locally in demo store
        store.submitRating(
          tripId: widget.tripId,
          ratedId: memberId,
          overallRating: rating,
          comment: comment,
        );

        // Submit to backend API
        try {
          await ApiClient.submitExperienceRating(
            tripId: widget.tripId,
            circleId: DEMO_CIRCLE_ID,
            ratedById: trip.shopperId,
            ratedId: memberId,
            overallRating: rating,
            comment: comment,
          );
        } catch (apiError) {
          // Log API error but continue with other ratings
          debugPrint('Failed to submit rating to API: $apiError');
        }
      }

      if (!mounted) return;

      // Try to refresh the compatibility cache
      try {
        await ApiClient.refreshCompatibilityCache(circleId: DEMO_CIRCLE_ID);
      } catch (cacheError) {
        debugPrint('Failed to refresh compatibility cache: $cacheError');
      }

      if (!mounted) return;

      // Navigate back to home
      popToRoot(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ratings saved. Thanks for the feedback!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving ratings: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(widget.tripId);
    final requesters = trip.requests.where((r) => r.taking).toList();

    if (requesters.isEmpty) {
      return FavorlyPage(
        topBar: const FTopBar(title: 'Feedback'),
        children: const [
          Notice('No neighbors to rate on this trip.', kind: NoticeKind.neutral),
        ],
        bottom: FButton(label: 'Done', onPressed: () => popToRoot(context)),
      );
    }

    return FavorlyPage(
      topBar: const FTopBar(title: 'Feedback'),
      children: [
        const PageTitle(
          'How did it go?',
          subtitle: 'Rate each neighbor to help us make better matches in the future.',
        ),
        Panel(
          dividerIndent: 68,
          children: [
            for (final requester in requesters)
              _SurveyRow(
                member: store.memberById(requester.requesterId),
                onRatingChanged: (rating) {
                  setState(() => _ratings[requester.requesterId] = rating);
                },
                onCommentChanged: (comment) {
                  setState(() => _comments[requester.requesterId] = comment);
                },
                rating: _ratings[requester.requesterId],
                comment: _comments[requester.requesterId],
              ),
          ],
        ),
      ],
      bottom: FButton(
        label: 'Submit feedback',
        onPressed: _submitting ? null : _submitRatings,
        busy: _submitting,
      ),
    );
  }
}

class _SurveyRow extends StatefulWidget {
  const _SurveyRow({
    required this.member,
    required this.onRatingChanged,
    required this.onCommentChanged,
    this.rating,
    this.comment,
  });

  final Member member;
  final Function(int) onRatingChanged;
  final Function(String) onCommentChanged;
  final int? rating;
  final String? comment;

  @override
  State<_SurveyRow> createState() => _SurveyRowState();
}

class _SurveyRowState extends State<_SurveyRow> {
  late TextEditingController _commentController;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: widget.comment ?? '');
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Avatar(widget.member, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.member.name, style: FType.bodyStrong),
                      const SizedBox(height: 4),
                      _StarRating(
                        rating: widget.rating ?? 0,
                        onChanged: (newRating) {
                          widget.onRatingChanged(newRating);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                if (_expanded)
                  const Icon(CupertinoIcons.chevron_up, size: 16, color: FColors.inkTertiary)
                else
                  const Icon(CupertinoIcons.chevron_down, size: 16, color: FColors.inkTertiary),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Optional feedback', style: FType.caption.copyWith(color: FColors.inkTertiary)),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: _commentController,
                  placeholder: 'Great work!',
                  maxLines: 3,
                  minLines: 3,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FColors.surface,
                    borderRadius: BorderRadius.circular(FRadius.md),
                    border: Border.all(color: FColors.hairline),
                  ),
                  onChanged: (text) {
                    widget.onCommentChanged(text.trim());
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating, required this.onChanged});

  final int rating;
  final Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 1; i <= 5; i++) ...[
          GestureDetector(
            onTap: () => onChanged(i),
            child: Icon(
              i <= rating ? CupertinoIcons.star_fill : CupertinoIcons.star,
              size: 18,
              color: i <= rating ? FColors.blue : FColors.inkTertiary,
            ),
          ),
          if (i < 5) const SizedBox(width: 6),
        ],
        const SizedBox(width: 8),
        if (rating > 0)
          Text(
            rating == 5
                ? 'Great!'
                : rating >= 4
                    ? 'Good'
                    : rating >= 3
                        ? 'Okay'
                        : 'Needs work',
            style: FType.caption.copyWith(color: FColors.inkTertiary),
          ),
      ],
    );
  }
}
