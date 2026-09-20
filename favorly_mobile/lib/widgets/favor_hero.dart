import 'package:flutter/cupertino.dart';

import '../services/trellis_client.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import 'people.dart';
import 'surfaces.dart';

/// The favor you are on, on the app's one saturated surface.
///
/// Three things, in this order: who you are helping, the one thing they need,
/// and the way to close it out. You are not running an errand, you are doing
/// something for Maya, so Maya is the biggest thing on the screen.
///
/// Everything that used to sit between those three — how long ago they asked,
/// how much effort the model scored it at, a paragraph about doing one favor
/// at a time — is gone. None of it changes what you do next.
class FavorHero extends StatelessWidget {
  const FavorHero({
    super.key,
    required this.favor,
    this.startedAt,
    this.action,
    this.onTap,
  });

  final FavorSuggestion favor;

  /// When you took it on, if this device is the one that took it.
  final DateTime? startedAt;

  final Widget? action;
  final VoidCallback? onTap;

  String get _name =>
      favor.requesterName.isEmpty ? 'a neighbor' : favor.requesterName;

  /// What to do, in the fewest words that are still true: the model's
  /// instruction when there is one, otherwise the neighbor's own request.
  String get _ask =>
      favor.action.isNotEmpty ? favor.action : favor.originalRequest;

  @override
  Widget build(BuildContext context) {
    const white = FColors.onAccent;
    final soft = white.withValues(alpha: 0.9);
    final since = agoLabel(startedAt);

    final card = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FRadius.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FColors.bluePressed, FColors.blue, FColors.blueBright],
          stops: [0, 0.55, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(right: -70, top: -100, child: Orb(size: 230, opacity: 0.12)),
          const Positioned(right: 30, bottom: -140, child: Orb(size: 210, opacity: 0.08)),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('You are helping', color: soft),
                const SizedBox(height: FSpace.md),
                Row(
                  children: [
                    InitialsAvatar(_name, size: 48, onAccent: true),
                    const SizedBox(width: FSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name,
                            style: FType.title.copyWith(color: white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (since.isNotEmpty)
                            Text(
                              'Started $since',
                              style: FType.caption.copyWith(color: soft),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_ask.isNotEmpty) ...[
                  const SizedBox(height: FSpace.lg),
                  Text(
                    _ask,
                    style: FType.body.copyWith(color: soft, height: 24 / 17),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: FSpace.xl),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Pressable(
      onTap: onTap,
      label: onTap == null ? null : 'Helping $_name, ${favor.title}',
      child: card,
    );
  }
}
