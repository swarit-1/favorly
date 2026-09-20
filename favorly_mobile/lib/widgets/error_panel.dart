import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A failure message you can actually read.
///
/// `InputDecoration.errorText` is a single ellipsized line, which hides exactly
/// the part you need — the URL that failed, the status, the reason. This wraps
/// instead, and the text is selectable so it can be copied into a bug report.
class ErrorPanel extends StatelessWidget {
  const ErrorPanel(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: FSpace.lg),
      padding: const EdgeInsets.all(FSpace.md),
      decoration: BoxDecoration(
        color: FColors.criticalTint,
        borderRadius: BorderRadius.circular(FRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: FSpace.sm),
            child: Icon(Icons.error_outline, size: 16, color: FColors.critical),
          ),
          Expanded(
            child: SelectableText(
              // Dart prefixes thrown Exceptions; the prefix is never the point.
              text.replaceFirst(RegExp(r'^Exception:\s*'), ''),
              style: FType.bodySmall.copyWith(color: FColors.critical),
            ),
          ),
        ],
      ),
    );
  }
}
