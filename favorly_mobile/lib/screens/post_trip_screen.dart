import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/common.dart';
import 'confirm_trip_screen.dart';

class PostTripScreen extends StatelessWidget {
  const PostTripScreen({super.key});

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
            Text('Post a trip', style: text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Tell your neighbors where you’re going and when. '
              'They can add their shopping requests.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 22),
            const _FieldLabel('Store'),
            const SizedBox(height: 8),
            const _SelectField(
              icon: Icons.shopping_basket_outlined,
              value: "Trader Joe's",
            ),
            const SizedBox(height: 18),
            const _FieldLabel('When are you going?'),
            const SizedBox(height: 8),
            const _SelectField(
              icon: Icons.calendar_today_rounded,
              value: 'Today, 3:00 PM',
            ),
            const SizedBox(height: 18),
            const _CapsCard(),
            const SizedBox(height: 22),
            PillButton(
              label: 'Say the trip',
              icon: Icons.mic_none_rounded,
              background: AppColors.greenTint,
              foreground: AppColors.green,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConfirmTripScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'Post trip',
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return OutlinedCard(
      onTap: () {},
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.green),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
          ),
          const Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted),
        ],
      ),
    );
  }
}

class _CapsCard extends StatelessWidget {
  const _CapsCard();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return OutlinedCard(
      padding: const EdgeInsets.all(18),
      background: const Color(0xFFFAF9F5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Keep it manageable', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            'These caps help keep trips friendly and fair for everyone.',
            style: text.bodyMedium?.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _CapRow(
            icon: Icons.groups_rounded,
            label: 'Up to 5 neighbors',
          ),
          const SizedBox(height: 14),
          const _CapRow(
            icon: Icons.monetization_on_rounded,
            label: '\$40 max per person',
          ),
          const SizedBox(height: 14),
          const _CapRow(
            icon: Icons.list_alt_rounded,
            label: '8 items per person',
          ),
        ],
      ),
    );
  }
}

class _CapRow extends StatelessWidget {
  const _CapRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Icon(icon, size: 24, color: AppColors.green),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}
