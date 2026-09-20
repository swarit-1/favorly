// DEV BYPASS: pick a seeded Supabase Auth account and become them. The account
// is real (fake @favorly.test email, shared dev password) so the token is a
// real JWT, you just don't have to type the password. Delete this file (and
// the `Dev login` entry on AuthStartScreen) once real auth is wired up.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/error_panel.dart';
import '../widgets/surfaces.dart';

class DevLoginScreen extends ConsumerStatefulWidget {
  const DevLoginScreen({super.key});

  @override
  ConsumerState<DevLoginScreen> createState() => _DevLoginScreenState();
}

class _DevLoginScreenState extends ConsumerState<DevLoginScreen> {
  final _name = TextEditingController();
  final _server = TextEditingController(text: ApiConfig.baseUrl);
  final _trellis = TextEditingController(text: ApiConfig.trellisBaseUrl);
  late Future<List<Map<String, dynamic>>> _users;
  String? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _users = ApiClient.devUsers();
  }

  @override
  void dispose() {
    _name.dispose();
    _server.dispose();
    _trellis.dispose();
    super.dispose();
  }

  /// Point the app at a different API without rebuilding. Paste a tunnel or
  /// deployed URL here and it persists across launches.
  Future<void> _applyServer() async {
    await ApiConfig.set(_server.text);
    if (!mounted) return;
    setState(() {
      _server.text = ApiConfig.baseUrl;
      _error = null;
      _users = ApiClient.devUsers();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('API set to ${ApiConfig.baseUrl}')),
    );
  }

  Future<void> _login(String name) async {
    if (name.trim().isEmpty || _isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    await ref.read(authProvider.notifier).devLogin(name: name.trim());

    if (!mounted) return;
    final authState = ref.read(authProvider);
    setState(() {
      _isLoading = false;
      _error = authState.error;
    });
    // On success main.dart swaps in RootShell; pop the auth stack behind it.
    if (authState.userId != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// The agent + graph service is a separate deployment from the errand API,
  /// so it gets its own address.
  Future<void> _applyTrellis() async {
    await ApiConfig.setTrellis(_trellis.text);
    if (!mounted) return;
    setState(() => _trellis.text = ApiConfig.trellisBaseUrl);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Agent API set to ${ApiConfig.trellisBaseUrl}')),
    );
  }

  /// Drop a saved override and go back to the build's default server.
  Future<void> _resetServer() async {
    await ApiConfig.reset();
    if (!mounted) return;
    setState(() {
      _server.text = ApiConfig.baseUrl;
      _trellis.text = ApiConfig.trellisBaseUrl;
      _error = null;
      _users = ApiClient.devUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FColors.canvas,
      appBar: AppBar(
        backgroundColor: FColors.canvas,
        elevation: 0,
        title: Text('Dev login', style: FType.body),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Text(
                  'Become anyone in the circle. These are real Supabase Auth '
                  'accounts with fake emails. The password is filled in for you.',
                  style: FType.bodySmall.copyWith(color: FColors.inkSecondary),
                ),
                const SizedBox(height: FSpace.xxl),
                const FieldLabel('Server'),
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'https://your-api.example.com',
                    helperText: 'Where the API lives. Saved on this device.',
                    helperStyle:
                        FType.caption.copyWith(color: FColors.inkTertiary),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check, color: FColors.blue),
                      tooltip: 'Use this server',
                      onPressed: _applyServer,
                    ),
                  ),
                  onSubmitted: (_) => _applyServer(),
                ),
                if (ApiConfig.isOverridden)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _resetServer,
                      child: Text(
                        'Reset to ${ApiConfig.compiledDefault}',
                        style: FType.caption.copyWith(color: FColors.blue),
                      ),
                    ),
                  ),
                const SizedBox(height: FSpace.xl),
                const FieldLabel('Agent API'),
                TextField(
                  controller: _trellis,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'https://favorly-agents.vercel.app',
                    helperText: 'Recommendations and favors. Separate service.',
                    helperStyle:
                        FType.caption.copyWith(color: FColors.inkTertiary),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.check, color: FColors.blue),
                      tooltip: 'Use this agent API',
                      onPressed: _applyTrellis,
                    ),
                  ),
                  onSubmitted: (_) => _applyTrellis(),
                ),
                const SizedBox(height: FSpace.xl),
                const FieldLabel('Email'),
                TextField(
                  controller: _name,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.go,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.email],
                  decoration: InputDecoration(
                    hintText: 'maya.chen@favorly.test',
                    helperText: 'A name works too, like "Maya Chen".',
                    helperStyle: FType.caption.copyWith(
                      color: FColors.inkTertiary,
                    ),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: _login,
                ),
                ErrorPanel(_error),
                const SizedBox(height: FSpace.xl),
                FButton(
                  label: _isLoading ? 'Logging in...' : 'Log in as this email',
                  onPressed: _isLoading ? null : () => _login(_name.text),
                ),
                const SizedBox(height: FSpace.xxxl),
                Text(
                  'OR TAP AN ACCOUNT',
                  style: FType.caption.copyWith(
                    color: FColors.inkTertiary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: FSpace.md),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _users,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(FSpace.xl),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      final offline =
                          snapshot.error is DevBypassUnavailable;
                      // This Future is built in initState, so a hot reload
                      // keeps showing a stale failure. Let it be re-run.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offline
                                ? '${snapshot.error}\n\n'
                                    'Use the Log in screen with one of the '
                                    '@favorly.test emails and the dev password.'
                                : 'Could not reach $apiBaseUrl\n'
                                    '${snapshot.error}',
                            style: FType.bodySmall.copyWith(
                              color: offline
                                  ? FColors.inkSecondary
                                  : FColors.critical,
                            ),
                          ),
                          const SizedBox(height: FSpace.sm),
                          TextButton(
                            onPressed: () => setState(
                                () => _users = ApiClient.devUsers()),
                            child: Text(
                              'Retry',
                              style:
                                  FType.caption.copyWith(color: FColors.blue),
                            ),
                          ),
                        ],
                      );
                    }
                    final users = snapshot.data ?? const [];
                    if (users.isEmpty) {
                      return Text(
                        'No seeded accounts yet. Run:\n'
                        'python backend/seed/seed_auth_users.py',
                        style: FType.bodySmall
                            .copyWith(color: FColors.inkSecondary),
                      );
                    }
                    return Column(
                      children: [
                        for (final user in users)
                          _PersonRow(
                            name: user['name'] as String,
                            email: user['email'] as String,
                            seeded: user['seeded'] as bool,
                            onTap: _isLoading
                                ? null
                                : () => _login(user['email'] as String),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.name,
    required this.email,
    required this.seeded,
    required this.onTap,
  });

  final String name;
  final String email;
  final bool seeded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FSpace.sm),
      child: Material(
        color: FColors.surface,
        borderRadius: BorderRadius.circular(FRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FSpace.lg,
              vertical: FSpace.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: FType.body),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: FType.caption
                            .copyWith(color: FColors.inkTertiary),
                      ),
                    ],
                  ),
                ),
                if (!seeded)
                  Text(
                    'no password',
                    style: FType.caption.copyWith(color: FColors.attention),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
