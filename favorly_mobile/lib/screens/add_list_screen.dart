import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../util/nav.dart';
import '../widgets/buttons.dart';
import '../widgets/capture.dart';
import '../widgets/page.dart';
import '../widgets/voice_sheet.dart';
import 'review_list_screen.dart';

/// Three equal ways in, one review screen out.
class AddListScreen extends ConsumerStatefulWidget {
  const AddListScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<AddListScreen> createState() => _AddListScreenState();
}

class _AddListScreenState extends ConsumerState<AddListScreen> {
  IntakeSource _source = IntakeSource.text;
  final _text = TextEditingController();
  String? _transcript;
  bool _captured = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canContinue => switch (_source) {
        IntakeSource.text => _text.text.trim().isNotEmpty,
        IntakeSource.voice => _transcript != null,
        IntakeSource.photo => true,
      };

  String get _ctaLabel => switch (_source) {
        IntakeSource.text || IntakeSource.voice => 'Review list',
        IntakeSource.photo => _captured ? 'Use this photo' : 'Take photo',
      };

  Future<void> _listen() async {
    final transcript = await showFavorlySheet<String>(
      context,
      builder: (_) => const VoiceCaptureSheet(
        title: 'Say your list',
        prompt: 'Try: “bananas, oat milk, and two lemons.”',
        transcript: DemoStore.voiceListTranscript,
      ),
    );
    if (transcript == null || !mounted) return;
    setState(() => _transcript = transcript);
  }

  void _continue() {
    if (_source == IntakeSource.photo && !_captured) {
      setState(() => _captured = true);
      return;
    }
    final drafts = ref.read(storeProvider).drafts(_source, text: _text.text);
    push(
      context,
      ReviewListScreen(tripId: widget.tripId, drafts: drafts, source: _source),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final trip = store.tripById(widget.tripId);
    final shopper = store.memberById(trip.shopperId);
    final caps = trip.caps;

    return FavorlyPage(
      topBar: FTopBar(title: trip.store),
      children: [
        PageTitle(
          'Add your list',
          subtitle: '${shopper.firstName} leaves ${dayLabel(trip.departAt).toLowerCase()} '
              'at ${clock(trip.departAt)}. Up to ${plural(caps.maxItemsPerPerson, 'item')}, '
              '${moneyShort(caps.maxDollarsPerPerson)} total.',
        ),
        SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<IntakeSource>(
            groupValue: _source,
            backgroundColor: FColors.surface,
            thumbColor: FColors.canvas,
            padding: const EdgeInsets.all(4),
            children: const {
              IntakeSource.text: _Segment('Type', CupertinoIcons.keyboard),
              IntakeSource.voice: _Segment('Say it', CupertinoIcons.mic),
              IntakeSource.photo: _Segment('Photo', CupertinoIcons.camera),
            },
            onValueChanged: (v) {
              if (v != null) setState(() => _source = v);
            },
          ),
        ),
        const SizedBox(height: 18),
        switch (_source) {
          IntakeSource.text => _TypePane(controller: _text, onChanged: () => setState(() {})),
          IntakeSource.voice => _VoicePane(transcript: _transcript, onListen: _listen),
          IntakeSource.photo => _PhotoPane(
              captured: _captured,
              onRetake: () => setState(() => _captured = false),
            ),
        },
      ],
      bottom: FButton(
        label: _ctaLabel,
        icon: _source == IntakeSource.photo && !_captured ? CupertinoIcons.camera_fill : null,
        onPressed: _canContinue ? _continue : null,
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment(this.label, this.icon);

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: FColors.ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: FType.captionStrong,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypePane extends StatelessWidget {
  const _TypePane({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          minLines: 5,
          maxLines: 9,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'One item per line\n2 lemons\noat milk, under \$5\nsourdough (a loaf)',
          ),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: 10),
        Text(
          'Add a cap like “under \$6” if you want one. Quantities and notes are picked up too.',
          style: FType.caption.copyWith(color: FColors.inkSecondary),
        ),
      ],
    );
  }
}

class _VoicePane extends StatelessWidget {
  const _VoicePane({required this.transcript, required this.onListen});

  final String? transcript;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    if (transcript == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: FColors.surface,
          borderRadius: BorderRadius.circular(FRadius.xl),
        ),
        child: Column(
          children: [
            MicButton(onPressed: onListen),
            const SizedBox(height: 14),
            Text(
              'Tap and say your list',
              style: FType.bodySmallStrong.copyWith(color: FColors.inkSecondary),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FColors.surface,
            borderRadius: BorderRadius.circular(FRadius.lg),
          ),
          child: Text(transcript!, style: FType.body),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: FTextButton('Say it again', icon: CupertinoIcons.mic, onPressed: onListen),
        ),
      ],
    );
  }
}

class _PhotoPane extends StatelessWidget {
  const _PhotoPane({required this.captured, required this.onRetake});

  final bool captured;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Viewfinder(
          hint: captured ? 'Sharp enough to read' : 'Fit the whole list in frame',
          background: const Color(0xFF6E4E33),
          child: const PaperNote(lines: DemoStore.handwrittenLines),
        ),
        if (captured) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(CupertinoIcons.checkmark_circle_fill, size: 16, color: FColors.success),
              const SizedBox(width: 6),
              Text('Photo taken', style: FType.captionStrong.copyWith(color: FColors.success)),
              const Spacer(),
              FTextButton('Retake', onPressed: onRetake),
            ],
          ),
        ],
      ],
    );
  }
}
