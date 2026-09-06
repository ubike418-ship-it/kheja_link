import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/states.dart';

/// Sign in and sign up.
///
/// The Supabase project requires email confirmation, so a new account does not
/// get a session immediately — the UI has to say "check your inbox" rather than
/// pretending the user is signed in.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.startOnSignUp = false});

  final bool startOnSignUp;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();

  late bool _isSignUp = widget.startOnSignUp;
  bool _isBusy = false;
  bool _showPassword = false;
  bool _awaitingConfirmation = false;
  String _role = 'seeker';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    _fullName.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isBusy = true);

    try {
      if (_isSignUp) {
        final response = await khejaApi.signUp(
          email: _email.text,
          password: _password.text,
          fullName: _fullName.text,
          phone: _phone.text,
          role: _role,
        );
        if (!mounted) return;

        if (response.session == null) {
          setState(() {
            _isBusy = false;
            _awaitingConfirmation = true;
          });
          return;
        }
        Navigator.of(context).pop(true);
      } else {
        await khejaApi.signIn(email: _email.text, password: _password.text);
        if (!mounted) return;
        showKhejaSnack(context, 'Welcome back.');
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showKhejaSnack(context, 'Enter your email address first.', isError: true);
      return;
    }
    try {
      await khejaApi.resetPassword(email);
    } catch (_) {
      // Deliberately silent: saying whether an address exists is an
      // account-enumeration leak.
    }
    if (!mounted) return;
    showKhejaSnack(context, 'If that address has an account, a reset link is on its way.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_awaitingConfirmation) {
      return Scaffold(
        appBar: AppBar(),
        body: KhejaEmptyState(
          icon: Icons.mark_email_read_rounded,
          title: 'Check your email',
          message: 'We sent a confirmation link to ${_email.text.trim()}. '
              'Tap it, then come back and sign in.',
          actionLabel: 'Back to sign in',
          onAction: () => setState(() {
            _awaitingConfirmation = false;
            _isSignUp = false;
          }),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: LogoLockup(width: 200)),
                const SizedBox(height: 24),
                Text(
                  _isSignUp ? 'Join Kheja_Link.' : 'Welcome back.',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  _isSignUp
                      ? 'Find your next home, or list one of your own.'
                      : 'Sign in to pick up where you left off.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: KhejaColors.zinc500),
                ),
                const SizedBox(height: 30),

                if (_isSignUp) ...[
                  _Label('I want to'),
                  Row(
                    children: [
                      Expanded(
                        child: _RoleCard(
                          selected: _role == 'seeker',
                          icon: Icons.home_rounded,
                          title: 'Find a house',
                          subtitle: 'Search and save homes',
                          onTap: () => setState(() => _role = 'seeker'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _RoleCard(
                          selected: _role == 'landlord',
                          icon: Icons.vpn_key_rounded,
                          title: 'List a house',
                          subtitle: 'Rent out my property',
                          onTap: () => setState(() => _role = 'landlord'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  _Label('Full name'),
                  TextFormField(
                    controller: _fullName,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(hintText: 'e.g. Amina Kimathi'),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Tell us your name'
                        : null,
                  ),
                  const SizedBox(height: 18),
                ],

                _Label('Email'),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(hintText: 'you@example.com'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    final valid =
                        RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
                    return valid ? null : 'Enter a valid email address';
                  },
                ),
                const SizedBox(height: 18),

                if (_isSignUp) ...[
                  _Label('Phone (optional)'),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(hintText: '+254 712 345 678'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      final digits = text.replaceAll(RegExp(r'\D'), '');
                      return digits.length >= 7
                          ? null
                          : 'Enter a valid phone number';
                    },
                  ),
                  const SizedBox(height: 18),
                ],

                _Label('Password'),
                TextFormField(
                  controller: _password,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    hintText: _isSignUp ? 'At least 8 characters' : '••••••••',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 20,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final text = value ?? '';
                    if (text.isEmpty) return 'Enter your password';
                    if (_isSignUp && text.length < 8) {
                      return 'Use at least 8 characters';
                    }
                    return null;
                  },
                ),

                if (_isSignUp) ...[
                  const SizedBox(height: 18),
                  _Label('Confirm password'),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: !_showPassword,
                    decoration: const InputDecoration(hintText: 'Repeat password'),
                    validator: (value) => value == _password.text
                        ? null
                        : 'Passwords do not match',
                  ),
                ],

                if (!_isSignUp) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _resetPassword,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Forgot your password?'),
                    ),
                  ),
                ],

                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _isBusy ? null : _submit,
                  child: _isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isSignUp ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 18),

                Center(
                  child: TextButton(
                    onPressed: _isBusy
                        ? null
                        : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _formKey.currentState?.reset();
                            }),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : 'New to Kheja_Link? Create an account',
                    ),
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text.toUpperCase(),
          style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? KhejaColors.blue : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.md),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.md),
            border: Border.all(
              color: selected ? KhejaColors.blue : theme.colorScheme.outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 20,
                  color: selected ? Colors.white : theme.colorScheme.onSurface),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: selected ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white70 : KhejaColors.zinc400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
