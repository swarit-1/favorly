import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/demo_store.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/surfaces.dart';

/// First run: a name and an invite code. No account, no password.
class JoinScreen extends ConsumerStatefulWidget {
  const JoinScreen({super.key});

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _canJoin => _name.text.trim().isNotEmpty && _code.text.trim().length == 6;

  void _join() {
    if (!_canJoin) return;
    final ok = ref.read(storeProvider).join(name: _name.text, code: _code.text);
    if (!ok) {
      setState(() => _error = 'That code doesn’t match a circle. Ask a neighbor for theirs.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                const SizedBox(height: 24),
                const _Wordmark(),
                const SizedBox(height: 12),
                Text(
                  'One neighbor’s trip carries the whole building.',
                  style: FType.body.copyWith(color: FColors.inkSecondary),
                ),
                const SizedBox(height: 36),
                const FieldLabel('Your name'),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  decoration: const InputDecoration(hintText: 'First and last'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 18),
                const FieldLabel('Invite code'),
                TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(6),
                    TextInputFormatter.withFunction(
                      (_, value) => value.copyWith(text: value.text.toUpperCase()),
                    ),
                  ],
                  style: FType.money.copyWith(letterSpacing: 2),
                  decoration: InputDecoration(hintText: 'ABC123', errorText: _error),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 8),
                Text(
                  'Demo code: ${DemoStore.inviteCode}',
                  style: FType.caption.copyWith(color: FColors.inkTertiary),
                ),
                const SizedBox(height: 28),
                FButton(label: 'Join circle', onPressed: _canJoin ? _join : null),
                const SizedBox(height: 14),
                Text(
                  'No account needed. Your name is what neighbors see.',
                  textAlign: TextAlign.center,
                  style: FType.caption.copyWith(color: FColors.inkSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Favorly',
          style: FType.display.copyWith(fontSize: 40, letterSpacing: -1.5),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 9),
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: FColors.blue, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}
