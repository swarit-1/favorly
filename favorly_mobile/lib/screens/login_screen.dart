import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/surfaces.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canLogin =>
      _email.text.trim().isNotEmpty && _password.text.isNotEmpty;

  Future<void> _login() async {
    if (!_canLogin) return;

    setState(() => _isLoading = true);

    await ref.read(authProvider.notifier).login(
          email: _email.text.trim(),
          password: _password.text,
        );

    if (!mounted) return;
    final authState = ref.read(authProvider);
    if (authState.error != null) {
      setState(() {
        _error = authState.error ?? 'Login failed';
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
                  'Welcome back to Favorly.',
                  style: FType.body.copyWith(color: FColors.inkSecondary),
                ),
                const SizedBox(height: 36),
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
                  textInputAction: TextInputAction.done,
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
                    errorText: _error,
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 28),
                FButton(
                  label: _isLoading ? 'Logging in...' : 'Log in',
                  onPressed: _canLogin && !_isLoading ? _login : null,
                ),
                const SizedBox(height: 14),
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Don't have an account? ",
                        style: FType.caption
                            .copyWith(color: FColors.inkSecondary),
                      ),
                      GestureDetector(
                        onTap: () =>
                            Navigator.of(context).pop(), // Go back to start
                        child: Text(
                          'Sign up',
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
