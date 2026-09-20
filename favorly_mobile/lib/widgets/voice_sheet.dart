import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'buttons.dart';
import 'capture.dart';
import 'page.dart';

/// Listens, then shows the transcript for approval. Pops with the transcript
/// when the person taps "Use this". The real app records audio here and
/// posts it to /parses; the flow stays identical.
class VoiceCaptureSheet extends StatefulWidget {
  const VoiceCaptureSheet({
    super.key,
    required this.prompt,
    required this.transcript,
    this.title = 'Say it',
  });

  final String prompt;
  final String transcript;
  final String title;

  @override
  State<VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<VoiceCaptureSheet> {
  bool _done = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _timer?.cancel();
    setState(() => _done = false);
    _timer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      children: [
        SheetTitle(
          widget.title,
          subtitle: _done ? 'Here’s what we heard' : 'Listening…',
        ),
        if (!_done)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const ListeningWave(height: 44),
                const SizedBox(height: 18),
                Text(
                  widget.prompt,
                  textAlign: TextAlign.center,
                  style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FColors.surface,
              borderRadius: BorderRadius.circular(FRadius.lg),
            ),
            child: Text(widget.transcript, style: FType.body),
          ),
        const SizedBox(height: 8),
      ],
      bottom: BottomActions(
        children: [
          if (_done)
            FButton(
              label: 'Use this',
              onPressed: () => Navigator.of(context).pop(widget.transcript),
            ),
          FButton(
            label: _done ? 'Try again' : 'Cancel',
            kind: FButtonKind.tertiary,
            onPressed: _done ? _listen : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
