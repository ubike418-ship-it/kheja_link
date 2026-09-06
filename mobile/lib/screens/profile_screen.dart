import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/states.dart';
import 'auth_screen.dart';
import 'my_listings_screen.dart';
import 'inquiries_screen.dart';

/// The account tab. Signed out it invites you in; signed in it shows your
/// profile and, for landlords, the way into listings and inquiries.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Future<Profile?>? _future;

  @override
  void initState() {
    super.initState();
    if (khejaApi.isSignedIn) _future = khejaApi.fetchProfile();
  }

  void _reload() {
    setState(() {
      _future = khejaApi.isSignedIn ? khejaApi.fetchProfile() : null;
    });
  }

  Future<void> _openAuth({bool signUp = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuthScreen(startOnSignUp: signUp)),
    );
    if (mounted) _reload();
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
        ),
        title: const Text('Sign out?'),
        content: const Text('You can sign back in at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: KhejaColors.red),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await khejaApi.signOut();
    if (!mounted) return;
    showKhejaSnack(context, 'Signed out.');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (!khejaApi.isSignedIn) return _signedOutView();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          IconButton(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<Profile?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: KhejaColors.blue),
            );
          }

          if (snapshot.hasError) {
            return KhejaErrorState(
              message: describeError(snapshot.error!),
              onRetry: _reload,
            );
          }

          final profile = snapshot.data;
          if (profile == null) {
            return KhejaErrorState(
              message: 'We could not load your profile.',
              onRetry: _reload,
            );
          }

          return _signedInView(profile);
        },
      ),
    );
  }

  Widget _signedOutView() {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const BrandLockup(size: 46, fontSize: 25),
              const Spacer(),
              Text('Your account.', style: theme.textTheme.displaySmall),
              const SizedBox(height: 12),
              Text(
                'Sign in to save homes you like, keep track of your messages, or '
                'list a property of your own.',
                style:
                    theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _openAuth(),
                child: const Text('Sign in'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _openAuth(signUp: true),
                child: const Text('Create an account'),
              ),
              const Spacer(),
              const _SupportLinks(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signedInView(Profile profile) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      color: KhejaColors.blue,
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: KhejaColors.blue,
                  borderRadius: BorderRadius.circular(KhejaRadius.lg),
                ),
                child: Text(
                  profile.firstName.isNotEmpty
                      ? profile.firstName[0].toUpperCase()
                      : 'K',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.fullName ?? 'Your account',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (profile.isVerified) ...[
                          const Icon(Icons.verified_rounded,
                              size: 14, color: KhejaColors.emerald),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          profile.role.toUpperCase(),
                          style:
                              kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          if (profile.isLandlord) ...[
            Text('Landlord', style: theme.textTheme.titleLarge),
            const SizedBox(height: 14),
            _Tile(
              icon: Icons.home_work_rounded,
              label: 'My listings',
              subtitle: 'Publish, edit and retire your houses',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyListingsScreen()),
              ),
            ),
            _Tile(
              icon: Icons.mark_email_unread_rounded,
              label: 'Inquiries',
              subtitle: 'People asking about your houses',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InquiriesScreen()),
              ),
            ),
            const SizedBox(height: 28),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: KhejaColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KhejaRadius.xl),
                border: Border.all(color: KhejaColors.blue.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.vpn_key_rounded, size: 20, color: KhejaColors.blue),
                      SizedBox(width: 10),
                      Text(
                        'Have a house to rent out?',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Switch to a landlord account and you can publish listings and '
                    'manage inquiries right here.',
                    style: TextStyle(
                      color: KhejaColors.zinc500,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => _becomeLandlord(profile),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('Become a landlord'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],

          Text('Your details', style: theme.textTheme.titleLarge),
          const SizedBox(height: 14),
          _Tile(
            icon: Icons.person_rounded,
            label: 'Edit profile',
            subtitle: profile.phone ?? 'Add a phone number',
            onTap: () => _editProfile(profile),
          ),
          const SizedBox(height: 28),

          const _SupportLinks(),
          const SizedBox(height: 28),

          OutlinedButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, size: 20),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(foregroundColor: KhejaColors.red),
          ),
        ],
      ),
    );
  }

  Future<void> _becomeLandlord(Profile profile) async {
    try {
      await khejaApi.updateProfile(
        fullName: profile.fullName ?? '',
        phone: profile.phone,
        bio: profile.bio,
        role: 'landlord',
      );
      if (!mounted) return;
      showKhejaSnack(context, 'You can now list houses on Kheja_Link.');
      _reload();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _editProfile(Profile profile) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditProfileSheet(profile: profile),
    );
    if (saved == true && mounted) {
      showKhejaSnack(context, 'Profile updated.');
      _reload();
    }
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KhejaRadius.lg),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: KhejaColors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KhejaRadius.sm),
                  ),
                  child: Icon(icon, size: 20, color: KhejaColors.blue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: KhejaColors.zinc500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: KhejaColors.zinc400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SupportLinks extends StatelessWidget {
  const _SupportLinks();

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showKhejaSnack(context, 'Could not open that link.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Support',
            style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _Link(
              label: 'Help & safety',
              onTap: () => _open(context, '${SupabaseConfig.siteUrl}/help'),
            ),
            _Link(
              label: 'Terms',
              onTap: () => _open(context, '${SupabaseConfig.siteUrl}/terms'),
            ),
            _Link(
              label: 'Privacy',
              onTap: () => _open(context, '${SupabaseConfig.siteUrl}/privacy'),
            ),
            _Link(
              label: 'hello@khejalink.co.ke',
              onTap: () => _open(context, 'mailto:hello@khejalink.co.ke'),
            ),
          ],
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: KhejaColors.blue,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profile});

  final Profile profile;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.fullName ?? '');
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  late final _bio = TextEditingController(text: widget.profile.bio ?? '');
  bool _isSaving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    try {
      await khejaApi.updateProfile(
        fullName: _name.text.trim(),
        phone: _phone.text,
        bio: _bio.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(KhejaRadius.xxl)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit profile', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 22),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name'),
                  validator: (value) =>
                      (value?.trim().length ?? 0) < 2 ? 'Tell us your name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    hintText: '+254 712 345 678',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final digits = text.replaceAll(RegExp(r'\D'), '');
                    return digits.length >= 7 ? null : 'Enter a valid phone number';
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _bio,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'About you',
                    hintText: 'Shown to house hunters on your listings.',
                  ),
                  validator: (value) => (value?.trim().length ?? 0) > 600
                      ? 'Keep your bio under 600 characters'
                      : null,
                ),
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
