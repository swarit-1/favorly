import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

class AuthStartScreen extends StatelessWidget {
  const AuthStartScreen({super.key});

  void _goToLogin(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
  }

  void _goToSignup(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SignupScreen()),
    );
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
                const SizedBox(height: 60),
                const _Wordmark(),
                const SizedBox(height: 12),
                Text(
                  "One neighbor's trip carries the whole building.",
                  style: FType.body.copyWith(color: FColors.inkSecondary),
                ),
                const SizedBox(height: 72),
                FButton(
                  label: 'Log in',
                  onPressed: () => _goToLogin(context),
                ),
                const SizedBox(height: 12),
                FButton(
                  label: 'Create account',
                  kind: FButtonKind.secondary,
                  onPressed: () => _goToSignup(context),
                ),
                const SizedBox(height: 32),
                Text(
                  'Favorly lets neighbors share trips to the store. Each member gets a say in what to buy.',
                  textAlign: TextAlign.center,
                  style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
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
