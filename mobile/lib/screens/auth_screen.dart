import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../main.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/states.dart';
import 'app_shell.dart';
import 'role_select_screen.dart';

/// Sign in and sign up, for one role at a time.
///
/// A tenant and a landlord see different screens with different wording and a
/// different colour, so nobody is unsure which door they are at. Sign-up
/// creates the account with that role.
///
/// On sign-in the role stored on the account is the source of truth: if a
/// landlord signs in through the tenant screen they are told so and taken to
/// the landlord app, rather than being dropped into the wrong interface.
class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.role,
    this.startOnSignUp = false,
    this.isEntryPoint = false,
  });

  /// 'seeker' or 'landlord'. Falls back to whatever door was chosen earlier.
  final String? role;
  final bool startOnSignUp;

  /// True when this is the first screen after choosing a role. On success it
  /// replaces itself with the app; otherwise it simply pops back.
  final bool isEntryPoint;

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

  String get _role => widget.role ?? AppState.instance.chosenRole ?? 'seeker';
  bool get _isLandlord => _role == 'landlord';
  Color get _accent => _isLandlord ? KhejaColors.emerald : KhejaColors.blue;

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

        // Email confirmation is on: there is no session until they click the
        // link, so say that plainly rather than pretending they are signed in.
        if (response.session == null) {
          setState(() {
            _isBusy = false;
            _awaitingConfirmation = true;
          });
          return;
        }
        await _enterApp();
      } else {
        await khejaApi.signIn(email: _email.text, password: _password.text);
        if (!mounted) return;
        await _enterApp();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  /// Sends the person to the right app for the account they actually have.
  Future<void> _enterApp() async {
    final profile = await khejaApi.fetchProfile();
    if (!mounted) return;

    final accountRole = (profile?.isLandlord ?? false) ? 'landlord' : 'seeker';

    if (accountRole != _role) {
      showKhejaSnack(
        context,
        accountRole == 'landlord'
            ? 'This is a landlord account — opening the landlord app.'
            : 'This is a tenant account — opening the tenant app.',
      );
    } else {
      showKhejaSnack(
        context,
        'Welcome${profile?.fullName != null ? ', ${profile!.firstName}' : ''}.',
      );
    }

    // The door they used should match the account from now on.
    await AppState.instance.setChosenRole(accountRole);
    if (!mounted) return;

    if (widget.isEntryPoint) {
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AppShell()),
        (_) => false,
      );
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _browseAsGuest() async {
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppShell()),
      (_) => false,
    );
  }

  Future<void> _switchRole() async {
    await AppState.instance.setChosenRole(null);
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
      (_) => false,
    );
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
          message: 'We sent a confirmation link to ${_email.text.trim()}. Tap it, '
              'then come back and sign in as a ${_isLandlord ? 'landlord' : 'tenant'}.',
          actionLabel: 'Back to sign in',
          onAction: () => setState(() {
            _awaitingConfirmation = false;
            _isSignUp = false;
          }),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isEntryPoint,
        actions: [
          if (widget.isEntryPoint)
            TextButton.icon(
              onPressed: _isBusy ? null : _switchRole,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: Text(_isLandlord ? "I'm a tenant" : "I'm a landlord"),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Which door this is, unmistakably.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isLandlord ? Icons.vpn_key_rounded : Icons.search_rounded,
                        size: 14,
                        color: _accent,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _isLandlord ? 'LANDLORD' : 'TENANT',
                        style: kEyebrowStyle.copyWith(color: _accent),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const LogoMark(size: 56),
                const SizedBox(height: 22),
                Text(
                  _isSignUp
                      ? (_isLandlord ? 'List your property.' : 'Find your home.')
                      : 'Welcome back.',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 10),
                Text(
                  _isSignUp
                      ? (_isLandlord
                          ? 'Create a landlord account to list houses, add photos and '
                              'video, and manage tenants.'
                          : 'Create a tenant account to save homes, get vacancy alerts '
                              'and unlock landlord contacts.')
                      : (_isLandlord
                          ? 'Sign in to manage your listings and tenants.'
                          : 'Sign in to pick up where you left off.'),
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: KhejaColors.zinc500, height: 1.5),
                ),
                const SizedBox(height: 30),

                if (_isSignUp) ...[
                  _Label(_isLandlord ? 'Your name' : 'Full name'),
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
                  // A landlord's phone is how tenants reach them, so it is required.
                  _Label(_isLandlord ? 'Phone number' : 'Phone (optional)'),
                  TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(hintText: '+254 712 345 678'),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) {
                        return _isLandlord
                            ? 'Tenants need a number to reach you'
                            : null;
                      }
                      final digits = text.replaceAll(RegExp(r'\D'), '');
                      return digits.length >= 9
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
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: _accent,
                      ),
                      child: const Text('Forgot your password?'),
                    ),
                  ),
                ],

                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _isBusy ? null : _submit,
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  child: _isBusy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isSignUp
                          ? (_isLandlord
                              ? 'Create landlord account'
                              : 'Create tenant account')
                          : (_isLandlord
                              ? 'Sign in as landlord'
                              : 'Sign in as tenant')),
                ),
                const SizedBox(height: 16),

                Center(
                  child: TextButton(
                    onPressed: _isBusy
                        ? null
                        : () => setState(() {
                              _isSignUp = !_isSignUp;
                              _formKey.currentState?.reset();
                            }),
                    style: TextButton.styleFrom(foregroundColor: _accent),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : (_isLandlord
                              ? 'New landlord? Create an account'
                              : 'New here? Create an account'),
                    ),
                  ),
                ),

                // Browsing is open to everyone, so a tenant can look before
                // committing. A landlord has nothing to do without an account.
                if (widget.isEntryPoint && !_isLandlord) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton(
                      onPressed: _isBusy ? null : _browseAsGuest,
                      style: TextButton.styleFrom(
                        foregroundColor: KhejaColors.zinc500,
                      ),
                      child: const Text('Just browsing — continue without an account'),
                    ),
                  ),
                ],
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
