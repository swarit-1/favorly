import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/trellis_client.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

/// The three people Favorly picked for an ask, each with the human reason.
///
/// 4.2 stub: header plus a quiet list, so the home card has somewhere real to
/// land. The person match cards, path strips, and the invite flow arrive in
/// phase 4.5.
class MatchesScreen extends ConsumerStatefulWidget {
  const MatchesScreen({
    super.key,
    required this.needId,
    required this.title,
    this.whenText = '',
    this.initialHelpers,
  });

  final String needId;
  final String title;
  final String whenText;

  /// Helpers already in hand (from the ask flow or the asks poll), so the
  /// screen can draw people immediately instead of a spinner.
  final List<HelperMatch>? initialHelpers;

  @override
  ConsumerState<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends ConsumerState<MatchesScreen> {
  // Grows an invite flow and a poll in 4.5; a plain field until then.
  late final List<HelperMatch> _helpers = widget.initialHelpers ?? const [];

  @override
  Widget build(BuildContext context) {
    return FavorlyPage(
      topBar: const FTopBar(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        PageTitle(
          widget.title,
          subtitle: widget.whenText.isEmpty ? null : widget.whenText,
          padding: const EdgeInsets.only(top: 4, bottom: 18),
        ),
        if (_helpers.isEmpty)
          const EmptyState(
            icon: CupertinoIcons.person_2,
            title: 'Finding the right neighbor',
            body: 'Favorly is looking around your circle. The three people '
                'worth asking land here.',
          )
        else
          Panel(
            dividerIndent: 74,
            children: [
              for (final helper in _helpers)
                PanelRow(
                  leading: InitialsAvatar(helper.displayName, size: 44),
                  title: helper.displayName,
                  subtitle: '${helper.headline} · ${helper.where}',
                  trailing: StatusPill(helper.tieLabel, kind: PillKind.info),
                ),
            ],
          ),
      ],
    );
  }
}
