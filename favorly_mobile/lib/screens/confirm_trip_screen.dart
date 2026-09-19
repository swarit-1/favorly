import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';

class ConfirmTripScreen extends StatelessWidget {
  const ConfirmTripScreen({super.key});

  static const _transcript =
      '“I’m going to Trader Joe’s at three, max five people, forty bucks each.”';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            const BackChevron(),
            const SizedBox(height: 10),
            Text('Here’s what we heard', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Check the details below before posting.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 20),
            const _TranscriptCard(transcript: _transcript),
            const SizedBox(height: 18),
            const _DetailList(),
            const SizedBox(height: 24),
            PillButton(
              label: 'Looks good — post',
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.transcript});

  final String transcript;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greenTint,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(
                icon: Icons.mic_rounded,
                background: AppColors.greenTintDeep,
                size: 46,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  transcript,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 22, color: AppColors.green),
              const SizedBox(width: 10),
              Text(
                'Converted to trip details',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.green.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailList extends StatelessWidget {
  const _DetailList();

  static const _rows = <_Detail>[
    _Detail(Icons.shopping_basket_outlined, 'Store', "Trader Joe's"),
    _Detail(Icons.calendar_today_rounded, 'Date & time', 'Today, 3:00 PM'),
    _Detail(Icons.groups_rounded, 'Number of neighbors', '5 neighbors'),
    _Detail(Icons.monetization_on_rounded, 'Max per person', '\$40 each'),
  ];

  @override
  Widget build(BuildContext context) {
    return OutlinedCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++) ...[
            _DetailRow(detail: _rows[i]),
            if (i != _rows.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 62,
                color: AppColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _Detail {
  const _Detail(this.icon, this.label, this.value);

  final IconData icon;
  final String label;
  final String value;
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.detail});

  final _Detail detail;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(detail.icon, size: 24, color: AppColors.green),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.value,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
