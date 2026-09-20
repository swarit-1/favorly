import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/error_panel.dart';
import '../widgets/surfaces.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _showPassword = false;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _canSignup =>
      _name.text.trim().isNotEmpty &&
      _email.text.trim().isNotEmpty &&
      _password.text.isNotEmpty &&
      _code.text.trim().length == 6;

  Future<void> _signup() async {
    if (!_canSignup) return;

    setState(() => _isLoading = true);

    await ref.read(authProvider.notifier).signup(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          inviteCode: _code.text.toUpperCase(),
        );

    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.error != null) {
      setState(() {
        _error = authState.error ?? 'Signup failed';
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
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
                  "One neighbor's trip carries the whole building.",
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
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 18),
                const FieldLabel('Email'),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(hintText: 'your@email.com'),
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 18),
                const FieldLabel('Password'),
                TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: FColors.inkTertiary,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  onChanged: (_) => setState(() => _error = null),
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
                      (_, value) =>
                          value.copyWith(text: value.text.toUpperCase()),
                    ),
                  ],
                  style: FType.money.copyWith(letterSpacing: 2),
                  decoration: InputDecoration(
                    hintText: 'ABC123',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _signup(),
                ),
                ErrorPanel(_error),
                const SizedBox(height: 28),
                FButton(
                  label: _isLoading ? 'Creating account...' : 'Sign up',
                  onPressed: _canSignup && !_isLoading ? _signup : null,
                ),
                const SizedBox(height: 14),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: FType.caption
                            .copyWith(color: FColors.inkSecondary),
                      ),
                      GestureDetector(
                        onTap: () =>
                            Navigator.of(context).pop(), // Go back to start
                        child: Text(
                          'Log in',
                          style: FType.caption.copyWith(
                            color: FColors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
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
            decoration:
                const BoxDecoration(color: FColors.blue, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}
