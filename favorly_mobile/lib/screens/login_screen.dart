import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/api_config.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/error_panel.dart';
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

  /// DEV BYPASS: in debug builds an email alone is enough — leave the password
  /// blank and we sign in as that account without it. Remove with real auth.
  bool get _isDevBypass => kDebugMode && _password.text.isEmpty;

  bool get _canLogin =>
      _email.text.trim().isNotEmpty &&
      (_password.text.isNotEmpty || _isDevBypass);

  Future<void> _login() async {
    if (!_canLogin) return;

    setState(() => _isLoading = true);

    final notifier = ref.read(authProvider.notifier);
    if (_isDevBypass) {
      await notifier.devLogin(name: _email.text.trim());
    } else {
      await notifier.login(
        email: _email.text.trim(),
        password: _password.text,
      );
    }

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
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _login(),
                ),
                ErrorPanel(_error),
                const SizedBox(height: 28),
                FButton(
                  label: _isLoading
                      ? 'Logging in...'
                      : _isDevBypass
                          ? 'Log in (dev, no password)'
                          : 'Log in',
                  onPressed: _canLogin && !_isLoading ? _login : null,
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Dev: leave the password blank to sign in as that email.',
                    textAlign: TextAlign.center,
                    style: FType.caption.copyWith(color: FColors.inkTertiary),
                  ),
                  const SizedBox(height: 4),
                  // Which server this is talking to. A saved override outlives
                  // rebuilds, so without this "why is it doing that" is a guess.
                  Text(
                    ApiConfig.baseUrl +
                        (ApiConfig.isOverridden ? '  (saved override)' : ''),
                    textAlign: TextAlign.center,
                    style: FType.caption.copyWith(
                      color: ApiConfig.isOverridden
                          ? FColors.attention
                          : FColors.inkTertiary,
                    ),
                  ),
                ],
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
