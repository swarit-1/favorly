import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/favor_category.dart';
import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/chips.dart';
import '../widgets/page.dart';
import '../widgets/surfaces.dart';
import '../widgets/voice_sheet.dart';
import 'add_list_screen.dart';
import 'standalone_request_screen.dart';

/// The composer: say what you need, in your own words, and Favorly finds the
/// neighbor. One field, because the parsing is the server's job, not a form's.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

/// Rotating examples: small, concrete, one per kind of favor, so the empty
/// field teaches the size of thing to ask for.
const _placeholders = [
  'Borrow a ladder for an hour',
  'Help me put up a shelf Saturday',
  'Walk the reservoir with me at 6',
  'Grab oat milk if you are out',
];

/// What a category chip drops into the field: the first few words of an ask,
/// never a finished sentence, so people keep talking in their own voice.
const _starters = <FavorCategory, String>{
  FavorCategory.errand: 'Pick up ',
  FavorCategory.borrow: 'Borrow ',
  FavorCategory.hands: 'Help me ',
  FavorCategory.skill: 'Show me how to ',
  FavorCategory.company: 'Join me for ',
  FavorCategory.ride: 'Give me a lift to ',
  FavorCategory.care: 'Keep an eye on ',
  FavorCategory.other: 'I could use a hand with ',
};

class _AskScreenState extends ConsumerState<AskScreen> {
  final _text = TextEditingController();
  Timer? _rotate;
  int _placeholderIndex = 0;
  FavorCategory? _chip;

  @override
  void initState() {
    super.initState();
    _rotate = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      // Only the hint rotates; never someone's words.
      if (mounted && _text.text.isEmpty) {
        setState(() {
          _placeholderIndex = (_placeholderIndex + 1) % _placeholders.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _rotate?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    final transcript = await showFavorlySheet<String>(
      context,
      builder: (_) => const VoiceCaptureSheet(
        title: 'Say what you need',
        prompt: 'Try: "I need to borrow a ladder for an hour today."',
        transcript: 'I need to borrow a ladder for an hour today',
      ),
    );
    if (transcript == null || !mounted) return;
    setState(() {
      _text.text = transcript;
      _chip = null;
    });
  }

  void _useStarter(FavorCategory category) {
    setState(() {
      // A chip only ever replaces an empty field or another chip's starter;
      // typed words are theirs and stay.
      final current = _text.text;
      final startedByChip =
          _chip != null && current == (_starters[_chip] ?? '');
      if (current.isEmpty || startedByChip) {
        _text.text = _starters[category] ?? '';
        _text.selection =
            TextSelection.collapsed(offset: _text.text.length);
        _chip = category;
      } else {
        _chip = category;
      }
    });
  }

  /// The old "Add your list" home button lives here now: grocery lists keep
  /// their own richer flow (items, caps, substitutions).
  void _snapList() {
    final store = ref.read(storeProvider);
    final active = store.activeTrip;
    final openTrip = [
      ...store.upcomingTrips.where((t) => t.status == TripStatus.open),
      if (active?.status == TripStatus.open) active!,
    ].firstOrNull;
    if (openTrip != null) {
      push(context, AddListScreen(tripId: openTrip.id));
    } else {
      push(context, const StandaloneRequestScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return FavorlyPage(
      topBar: const FTopBar(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const PageTitle(
          'What do you need a hand with?',
          subtitle: 'Say it like you would to a neighbor in the hall.',
          padding: EdgeInsets.only(top: 4, bottom: 18),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _text,
                minLines: 3,
                maxLines: 6,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _placeholders[_placeholderIndex],
                ),
              ),
            ),
            const SizedBox(width: FSpace.sm),
            FIconButton(
              icon: CupertinoIcons.mic,
              label: 'Say it instead',
              filled: true,
              color: FColors.blue,
              onPressed: _listen,
            ),
          ],
        ),
        const SizedBox(height: FSpace.lg),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final category in FavorCategory.values) ...[
                SelectChip(
                  label: category.label,
                  icon: category.icon,
                  selected: _chip == category,
                  onTap: () => _useStarter(category),
                ),
                if (category != FavorCategory.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: FSpace.xxl),
        Panel(
          children: [
            PanelRow(
              leading: const LeadingIcon(
                CupertinoIcons.camera,
                color: FColors.blue,
                background: FColors.blueTint,
              ),
              title: 'Have a grocery list? Snap it',
              subtitle: 'Lists ride along on a neighbor\'s trip.',
              onTap: _snapList,
            ),
          ],
        ),
      ],
      bottom: FButton(
        label: 'Find my neighbor',
        icon: CupertinoIcons.sparkles,
        // TODO(4.4): wire to POST /needs/intake with the three-step loading
        // states, scope handling, and the errand route into the list flow.
        onPressed: _text.text.trim().isEmpty ? null : () {},
      ),
    );
  }
}
