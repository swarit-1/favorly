import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/models.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/page.dart';
import '../widgets/people.dart';
import '../widgets/surfaces.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key, this.onComplete});

  final VoidCallback? onComplete;

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  late TextEditingController _bioController;
  late TextEditingController _unitController;
  late TextEditingController _floorController;
  late TextEditingController _buzzerController;
  late TextEditingController _notesController;
  Set<String> _selectedDietary = {};
  Set<String> _selectedStores = {};
  Set<String> _selectedDays = {};
  ShopperRole _selectedRole = ShopperRole.both;
  String? _photoPath;

  static const List<String> dietaryOptions = [
    'Vegetarian',
    'Vegan',
    'Gluten-free',
    'Halal',
    'Kosher',
    'Dairy-free',
    'Nut-free',
    'Shellfish-free',
    'Low-sodium',
    'No pork',
  ];

  static const List<String> storeOptions = [
    'Trader Joe\'s',
    'Whole Foods',
    'Costco',
    'Target',
    'Kroger',
    'Safeway',
    'Other',
  ];

  static const List<String> dayOptions = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    final me = store.me;

    _bioController = TextEditingController(text: me.bio ?? '');
    _unitController =
        TextEditingController(text: me.address?.unit ?? '');
    _floorController =
        TextEditingController(text: me.address?.floor ?? '');
    _buzzerController =
        TextEditingController(text: me.address?.buzzer ?? '');
    _notesController =
        TextEditingController(text: me.address?.notes ?? '');
    _photoPath = me.photoPath;
    _selectedDietary = Set.from(me.dietary);
    _selectedStores = Set.from(me.stores);
    _selectedDays = Set.from(me.availability);
    _selectedRole = me.role;
  }

  @override
  void dispose() {
    _bioController.dispose();
    _unitController.dispose();
    _floorController.dispose();
    _buzzerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Text('Choose from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(source: source);
    if (image != null) {
      setState(() => _photoPath = image.path);
    }
  }

  void _removePhoto() {
    setState(() => _photoPath = null);
  }

  Future<void> _save() async {
    final store = ref.read(storeProvider);
    final authState = ref.read(authProvider);

    final bio = _bioController.text.trim().isEmpty ? null : _bioController.text.trim();
    final address = MemberAddress(
      unit: _unitController.text.trim().isEmpty ? null : _unitController.text.trim(),
      floor: _floorController.text.trim().isEmpty ? null : _floorController.text.trim(),
      buzzer: _buzzerController.text.trim().isEmpty ? null : _buzzerController.text.trim(),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
    );

    // Update local state immediately
    store.updateProfile(
      photoPath: _photoPath,
      bio: bio,
      address: address,
      dietary: _selectedDietary.toList(),
      stores: _selectedStores.toList(),
      availability: _selectedDays.toList(),
      role: _selectedRole,
    );

    // If authenticated, persist to backend
    if (authState.userId != null && authState.accessToken != null) {
      try {
        await ApiClient.updateProfile(
          userId: authState.userId!,
          accessToken: authState.accessToken!,
          bio: bio,
          photoUrl: _photoPath,
          role: _selectedRole.name,
          address: {
            'unit': address.unit,
            'floor': address.floor,
            'buzzer': address.buzzer,
            'notes': address.notes,
          },
          dietary: _selectedDietary.isEmpty ? null : _selectedDietary.toList(),
          preferredStores: _selectedStores.isEmpty ? null : _selectedStores.toList(),
          availability: _selectedDays.isEmpty ? null : _selectedDays.toList(),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save profile: $e')),
          );
        }
        return;
      }
    }

    widget.onComplete?.call();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(storeProvider);
    final me = store.me;

    return FavorlyPage(
      topBar: const FTopBar(title: 'Edit Profile'),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      children: [
        Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_photoPath != null && _photoPath!.isNotEmpty)
                CircleAvatar(
                  radius: 50,
                  backgroundImage: FileImage(File(_photoPath!)),
                )
              else
                Avatar(me, size: 100),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: FColors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(CupertinoIcons.camera_fill,
                        size: 16, color: Colors.white),
                    onPressed: _pickPhoto,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_photoPath != null) ...[
          const SizedBox(height: 8),
          Center(
            child: FTextButton(
              'Remove photo',
              color: FColors.critical,
              onPressed: _removePhoto,
            ),
          ),
        ],
        const SizedBox(height: 24),
        const SectionHeader('Basic Info'),
        const FieldLabel('Short bio'),
        TextField(
          controller: _bioController,
          maxLength: 120,
          maxLines: 2,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Hi, I\'m a Trader Joe\'s regular…',
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('Address & Delivery'),
        Panel(
          dividerIndent: 0,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Unit / Apt #'),
                  TextField(
                    controller: _unitController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: '3B'),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Floor'),
                  TextField(
                    controller: _floorController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: '3'),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Entry code / Buzzer'),
                  TextField(
                    controller: _buzzerController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: '#123'),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Delivery notes'),
                  TextField(
                    controller: _notesController,
                    textInputAction: TextInputAction.done,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Leave with doorman, ring bell',
                      counterText: '',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader('Dietary Preferences'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in dietaryOptions)
              FilterChip(
                label: Text(option),
                selected: _selectedDietary.contains(option),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedDietary.add(option);
                    } else {
                      _selectedDietary.remove(option);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        const SectionHeader('Shopping Profile'),
        const FieldLabel('Role preference'),
        Wrap(
          spacing: 8,
          children: [
            SegmentedButton<ShopperRole>(
              segments: const [
                ButtonSegment(value: ShopperRole.shopper, label: Text('Shopper')),
                ButtonSegment(value: ShopperRole.requester, label: Text('Requester')),
                ButtonSegment(value: ShopperRole.both, label: Text('Both')),
              ],
              selected: {_selectedRole},
              onSelectionChanged: (selected) {
                setState(() => _selectedRole = selected.first);
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        const FieldLabel('Preferred stores'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in storeOptions)
              FilterChip(
                label: Text(option),
                selected: _selectedStores.contains(option),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedStores.add(option);
                    } else {
                      _selectedStores.remove(option);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        const FieldLabel('Available days'),
        Wrap(
          spacing: 8,
          children: [
            for (final day in dayOptions)
              FilterChip(
                label: Text(day),
                selected: _selectedDays.contains(day),
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedDays.add(day);
                    } else {
                      _selectedDays.remove(day);
                    }
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 28),
        FButton(label: 'Save Profile', onPressed: _save),
      ],
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: FType.bodySmallStrong.copyWith(color: FColors.ink),
      ),
    );
  }
}
