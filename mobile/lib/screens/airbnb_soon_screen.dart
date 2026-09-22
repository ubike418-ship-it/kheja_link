import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/states.dart';

/// Stays — short-term, Airbnb-style accommodation. Announced, not built.
///
/// Kheja_Link is a long-term rentals product first. This page says what Stays
/// will be, and collects hosts who want to hear first. There is deliberately
/// nothing behind it: no listings, no booking, no host dashboard — so nobody
/// can wander into an unfinished feature.
class AirbnbSoonScreen extends StatelessWidget {
  const AirbnbSoonScreen({super.key, this.isRoot = true});

  final bool isRoot;

  static const _plans = <({IconData icon, String title, String body})>[
    (
      icon: Icons.nightlight_round,
      title: 'Short-term stays',
      body: 'Furnished places for a night, a weekend or a few weeks — priced by '
          'the night, not by the month.',
    ),
    (
      icon: Icons.luggage_rounded,
      title: 'Holiday and temporary accommodation',
      body: 'Somewhere to stay while visiting Meru, or between homes.',
    ),
    (
      icon: Icons.verified_user_rounded,
      title: 'Verified hosts',
      body: 'Hosts are onboarded by the Kheja_Link team before they can list.',
    ),
  ];

  Future<void> _join(BuildContext context) async {
    final joined = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WaitlistSheet(),
    );
    if (joined == true && context.mounted) {
      showKhejaSnack(context, 'You are on the list. We will contact you before Stays opens.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isRoot,
        title: const Text('Stays'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        children: [
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            KhejaColors.purple.withValues(alpha: 0.22),
                            KhejaColors.blue.withValues(alpha: 0.10),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const LogoMark(size: 78),
                  ],
                ),
                const SizedBox(height: 26),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: KhejaColors.amber,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'COMING SOON',
                    style: kEyebrowStyle.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Stays — coming soon.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  'Short-term stays and Airbnb-style accommodation are coming to '
                  'Kheja_Link. They are not open yet.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: KhejaColors.zinc500, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),

          Text('What Stays will be',
              style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
          const SizedBox(height: 16),

          for (final plan in _plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(KhejaRadius.xl),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: KhejaColors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(KhejaRadius.md),
                      ),
                      child: Icon(plan.icon, size: 20, color: KhejaColors.purple),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(plan.title, style: theme.textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            plan.body,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: KhejaColors.zinc500,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: KhejaColors.purple.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(KhejaRadius.xl),
              border: Border.all(color: KhejaColors.purple.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Have a place you would let by the night?',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  'Leave your details and the Kheja_Link team will contact you before '
                  'Stays opens. Joining the list does not list anything yet.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: KhejaColors.zinc500,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _join(context),
                    style: FilledButton.styleFrom(backgroundColor: KhejaColors.purple),
                    icon: const Icon(Icons.notifications_active_rounded, size: 20),
                    label: const Text("I'm interested in becoming a Stays host"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WaitlistSheet extends StatefulWidget {
  const _WaitlistSheet();

  @override
  State<_WaitlistSheet> createState() => _WaitlistSheetState();
}

class _WaitlistSheetState extends State<_WaitlistSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _location = TextEditingController();
  final _count = TextEditingController();
  final _message = TextEditingController();
  String? _type;
  bool _saving = false;

  static const _types = ['Apartment', 'Bedsitter / studio', 'Room in my home', 'Whole house', 'Other'];

  @override
  void initState() {
    super.initState();
    final email = khejaApi.currentUser?.email;
    if (email != null) _email.text = email;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _location, _count, _message]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await khejaApi.joinStaysWaitlist(
        fullName: _name.text,
        phone: _phone.text,
        email: _email.text,
        location: _location.text,
        propertyCount: int.tryParse(_count.text.trim()),
        propertyType: _type,
        message: _message.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showKhejaSnack(context, describeError(error), isError: error is! AlreadyOnWaitlistException);
      if (error is AlreadyOnWaitlistException) Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(KhejaRadius.xl)),
        ),
        child: Form(
          key: _form,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: KhejaColors.zinc300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Join the Stays host list', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              const Text(
                'Only what we need to reach you. A phone number or an email is enough.',
                style: TextStyle(color: KhejaColors.zinc500, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Your name'),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Tell us your name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone', hintText: '+254 712 345 678'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) {
                    return _email.text.trim().isEmpty ? 'Add a phone number or an email' : null;
                  }
                  return RegExp(r'^\+?[\d\s-]{7,20}$').hasMatch(t) ? null : 'Enter a valid phone number';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Enter a valid email';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _location,
                decoration: const InputDecoration(labelText: 'Where is the place?', hintText: 'e.g. Milimani, Meru'),
                validator: (v) => (v?.length ?? 0) > 120 ? 'Keep it short' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'How many?'),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return null;
                        final n = int.tryParse(t);
                        return (n == null || n < 1 || n > 500) ? '1 to 500' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [
                        for (final t in _types) DropdownMenuItem(value: t, child: Text(t)),
                      ],
                      onChanged: (v) => setState(() => _type = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _message,
                maxLines: 3,
                maxLength: 1000,
                decoration: const InputDecoration(labelText: 'Anything else? (optional)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: KhejaColors.purple,
                  minimumSize: const Size.fromHeight(56),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Join the list'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
