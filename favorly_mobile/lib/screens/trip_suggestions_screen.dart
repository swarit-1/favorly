import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/capture.dart';
import '../widgets/error_panel.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

/// Screen showing potential favor requests that match the newly-created trip.
class TripSuggestionsScreen extends StatefulWidget {
  const TripSuggestionsScreen({
    super.key,
    required this.tripId,
    required this.store,
    this.departAt,
  });

  final String tripId;
  final String store;
  final DateTime? departAt;

  @override
  State<TripSuggestionsScreen> createState() => _TripSuggestionsScreenState();
}

class _TripSuggestionsScreenState extends State<TripSuggestionsScreen> {
  late Future<List<Map<String, dynamic>>> _suggestionsFuture;

  @override
  void initState() {
    super.initState();
    _suggestionsFuture = ApiClient.getTripSuggestions(widget.tripId);
  }

  @override
  Widget build(BuildContext context) {
    return FavorlyPage(
      topBar: const FTopBar(),
      children: [
        const PageTitle('Generating potential favor requests...'),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _suggestionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: ShimmerRows(count: 3),
              );
            }

            if (snapshot.hasError) {
              return ErrorPanel(snapshot.error.toString());
            }

            final suggestions = snapshot.data ?? [];

            if (suggestions.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'No matches found',
                  body:
                      'No one in your circle is looking for items from ${widget.store}.',
                ),
              );
            }

            return Panel(
              children: [
                for (final suggestion in suggestions)
                  _SuggestionCard(
                    requestId: suggestion['request_id'] as String,
                    requesterName:
                        suggestion['requester_name'] as String,
                    items: List<String>.from(
                      suggestion['items'] as List? ?? [],
                    ),
                    nudge: suggestion['nudge'] as String,
                    store: widget.store,
                  ),
              ],
            );
          },
        ),
      ],
      bottom: Padding(
        padding: const EdgeInsets.all(16),
        child: FButton(
          label: 'Done',
          onPressed: () {
            Navigator.of(context).popUntil(
              (route) => route.isFirst,
            );
          },
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.requestId,
    required this.requesterName,
    required this.items,
    required this.nudge,
    required this.store,
  });

  final String requestId;
  final String requesterName;
  final List<String> items;
  final String nudge;
  final String store;

  @override
  Widget build(BuildContext context) {
    final itemSummary = items.isEmpty
        ? 'some items'
        : items.length <= 3
            ? items.join(', ')
            : '${items.take(3).join(', ')} +${items.length - 3} more';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: FColors.hairline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialsAvatar(requesterName, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requesterName,
                      style: FType.bodyStrong,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      itemSummary,
                      style: FType.bodySmall.copyWith(
                        color: FColors.inkSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.auto_awesome,
                  size: 12,
                  color: FColors.blue,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  nudge,
                  style: FType.caption.copyWith(
                    color: FColors.inkTertiary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
