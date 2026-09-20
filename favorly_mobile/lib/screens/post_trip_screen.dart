import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/trip_provider.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'confirm_trip_screen.dart';

class PostTripScreen extends ConsumerStatefulWidget {
  const PostTripScreen({super.key});

  @override
  ConsumerState<PostTripScreen> createState() => _PostTripScreenState();
}

class _PostTripScreenState extends ConsumerState<PostTripScreen> {
  String? selectedStore = "Trader Joe's";
  DateTime? selectedTime = DateTime.now().add(const Duration(hours: 3));
  bool isLoading = false;

  Future<void> _postTrip() async {
    if (selectedStore == null || selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select store and time')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final authState = ref.read(authProvider);
      if (authState.userId == null) {
        throw Exception('Not authenticated');
      }

      final tripId = await ref.read(tripsProvider.notifier).createTrip(
            store: selectedStore!,
            departAt: selectedTime!,
            userId: authState.userId!,
          );

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip created successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tripsState = ref.watch(tripsProvider);

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
              'Tell your neighbors where you are going and when. '
              'They can add their shopping requests.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 22),
            const _FieldLabel('Store'),
            const SizedBox(height: 8),
            _SelectField(
              icon: Icons.shopping_basket_outlined,
              value: selectedStore ?? "Select store",
              onTap: () => _showStoreSelector(context),
            ),
            const SizedBox(height: 18),
            const _FieldLabel('When are you going?'),
            const SizedBox(height: 8),
            _SelectField(
              icon: Icons.calendar_today_rounded,
              value: selectedTime != null
                  ? selectedTime!.toString().split('.')[0]
                  : 'Select time',
              onTap: () => _showTimeSelector(context),
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
              label: isLoading ? 'Creating trip...' : 'Post trip',
              onPressed: isLoading ? null : _postTrip,
            ),
            if (tripsState.error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  tripsState.error!,
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showStoreSelector(BuildContext context) async {
    const stores = [
      "Trader Joe's",
      "Whole Foods",
      "Safeway",
      "CVS",
      "Walgreens",
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: stores
            .map((store) => ListTile(
                  title: Text(store),
                  onTap: () => Navigator.pop(context, store),
                ))
            .toList(),
      ),
    );

    if (selected != null) {
      setState(() => selectedStore = selected);
    }
  }

  Future<void> _showTimeSelector(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: selectedTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );

    if (selected != null) {
      if (mounted) {
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(selectedTime ?? DateTime.now()),
        );

        if (time != null) {
          setState(() {
            selectedTime = DateTime(
              selected.year,
              selected.month,
              selected.day,
              time.hour,
              time.minute,
            );
          });
        }
      }
    }
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
  const _SelectField({
    required this.icon,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedCard(
      onTap: onTap,
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
