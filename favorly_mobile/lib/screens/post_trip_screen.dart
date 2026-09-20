import 'package:flutter/material.dart';

import '../api_client.dart';
import '../config.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'confirm_trip_screen.dart';

class PostTripScreen extends StatefulWidget {
  const PostTripScreen({super.key, this.apiClient});

  final ApiClient? apiClient;

  @override
  State<PostTripScreen> createState() => _PostTripScreenState();
}

class _PostTripScreenState extends State<PostTripScreen> {
  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final _storeController = TextEditingController(text: "Trader Joe's");
  DateTime _departAt = DateTime.now().add(const Duration(hours: 2));
  bool _posting = false;

  @override
  void dispose() {
    _storeController.dispose();
    super.dispose();
  }

  Future<void> _pickDepartAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departAt),
    );
    if (time == null) return;
    setState(() {
      _departAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  String get _departAtLabel {
    final now = DateTime.now();
    final isToday = _departAt.year == now.year && _departAt.month == now.month && _departAt.day == now.day;
    final hour = _departAt.hour % 12 == 0 ? 12 : _departAt.hour % 12;
    final minute = _departAt.minute.toString().padLeft(2, '0');
    final ampm = _departAt.hour < 12 ? 'AM' : 'PM';
    return '${isToday ? 'Today' : '${_departAt.month}/${_departAt.day}'}, $hour:$minute $ampm';
  }

  Future<void> _postTrip() async {
    if (_storeController.text.trim().isEmpty) return;
    setState(() => _posting = true);
    try {
      await _api.createTrip(
        shopperId: AppConfig.currentUserId,
        circleId: AppConfig.demoCircleId,
        store: _storeController.text.trim(),
        departAt: _departAt,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not post trip: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

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
            _EditableField(
              icon: Icons.shopping_basket_outlined,
              controller: _storeController,
            ),
            const SizedBox(height: 18),
            const _FieldLabel('When are you going?'),
            const SizedBox(height: 8),
            _SelectField(
              icon: Icons.calendar_today_rounded,
              value: _departAtLabel,
              onTap: _pickDepartAt,
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
              label: _posting ? 'Posting…' : 'Post trip',
              onPressed: _posting ? null : _postTrip,
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

class _EditableField extends StatelessWidget {
  const _EditableField({required this.icon, required this.controller});

  final IconData icon;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return OutlinedCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.green),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({required this.icon, required this.value, this.onTap});

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
