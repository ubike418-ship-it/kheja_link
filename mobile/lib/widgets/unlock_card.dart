import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../screens/payment_sheet.dart';
import '../services/payments.dart';
import 'kheja_sheet.dart';
import 'states.dart';

/// The contact unlock: one price for every listing (contact_unlock_fee, KSh
/// 500 by default), charged when the tenant taps "Unlock contact". It opens
/// the contacts and the exact location for contact_unlock_hours (3), after
/// which the listing locks again.
///
/// The card deliberately shows no price. It first appears on the payment
/// screen after the tap, read from the checkout the database created, so the
/// tenant sees exactly what M-Pesa will charge before approving it.
///
/// While locked, the phone number, WhatsApp and exact map position genuinely
/// do not exist on the client — the database refuses to send them. This widget
/// is a storefront for that fact, not the thing enforcing it.
///
/// Paying happens in Kheja_Link's own payment screen: the tenant enters their
/// M-Pesa number and approves the prompt without leaving the app.
class UnlockCard extends StatefulWidget {
  const UnlockCard({
    super.key,
    required this.property,
    required this.contact,
    required this.onUnlocked,
    required this.onRequireSignIn,
  });

  final Property property;
  final PropertyContact contact;
  final Future<void> Function() onUnlocked;
  final Future<bool> Function() onRequireSignIn;

  @override
  State<UnlockCard> createState() => _UnlockCardState();
}

class _UnlockCardState extends State<UnlockCard> {
  bool _busy = false;
  bool _awaitingReturn = false;

  /// For the unlock duration in the copy. The price is not shown here.
  BusinessSettings _settings = const BusinessSettings();

  /// Keeps "2h 13m left" current, and locks the card again when the window
  /// closes — by asking the database, which stops sending the details.
  Timer? _tick;
  Timer? _expiry;

  @override
  void initState() {
    super.initState();
    khejaApi.cachedBusinessSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
    khejaApi.fetchBusinessSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(UnlockCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contact.unlockedUntil != widget.contact.unlockedUntil ||
        oldWidget.contact.unlocked != widget.contact.unlocked) {
      _scheduleExpiry();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _expiry?.cancel();
    super.dispose();
  }

  void _scheduleExpiry() {
    _tick?.cancel();
    _expiry?.cancel();
    final until = widget.contact.unlockedUntil;
    if (!widget.contact.unlocked || until == null) return;
    final left = until.difference(DateTime.now());
    if (left.isNegative) {
      widget.onUnlocked();
      return;
    }
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _expiry = Timer(left + const Duration(seconds: 2), () {
      if (!mounted) return;
      widget.onUnlocked();
      showKhejaSnack(context, 'Your ${_settings.unlockHours}-hour unlock for this home has ended.');
    });
  }

  String _timeLeft(DateTime until) {
    final left = until.difference(DateTime.now());
    if (left.inMinutes < 1) return 'less than a minute left';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m left' : '${m}m left';
  }

  Future<void> _launch(Uri uri, String failure) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showKhejaSnack(context, failure, isError: true);
  }

  Future<void> _startUnlock() async {
    if (!khejaApi.isSignedIn) {
      final signedIn = await widget.onRequireSignIn();
      if (!signedIn) return;
    }

    setState(() => _busy = true);

    // The database prices the checkout and resumes one already open, so a
    // second tap never opens a second charge.
    final UnlockCheckout checkout;
    try {
      checkout = await khejaApi.startContactUnlock(widget.property.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showKhejaSnack(context, describeError(error), isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);

    // Already paid for (perhaps on another device)? Nothing to buy.
    final reference = checkout.reference;
    if (checkout.alreadyUnlocked || reference == null) {
      await widget.onUnlocked();
      return;
    }

    final paid = await showKhejaSheet<bool>(
      context,
      PaymentSheet(
        reference: reference,
        amountLabel: checkout.amountLabel,
        title: 'Unlock contact',
        what: 'Landlord and caretaker numbers and the exact location for '
            '"${widget.property.title}", open for ${_settings.unlockHours} hours.',
        cardCheckoutUrl: () => KhejaCheckout.cardCheckoutUrl(reference),
      ),
    );

    if (!mounted) return;
    if (paid == true) {
      showKhejaSnack(context, 'Unlocked for ${_settings.unlockHours} hours. The details are below.');
    } else {
      setState(() => _awaitingReturn = true);
    }
    await widget.onUnlocked();
  }

  Future<void> _recheck() async {
    setState(() => _busy = true);
    await widget.onUnlocked();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!widget.contact.unlocked) {
      showKhejaSnack(
        context,
        'No payment found yet. If you have just paid, give it a few seconds.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.contact.unlocked ? _unlocked(context) : _locked(context);
  }

  // ---------------------------------------------------------------------------
  // Unlocked
  // ---------------------------------------------------------------------------
  Widget _unlocked(BuildContext context) {
    final c = widget.contact;
    final title = widget.property.title;

    String? digits(String? raw) {
      final cleaned = raw?.replaceAll(RegExp(r'[^\d+]'), '');
      if (cleaned == null) return null;
      return cleaned.replaceAll('+', '').length < 9 ? null : cleaned;
    }

    final landlordPhone = digits(c.phone);
    final whatsapp = digits(c.whatsapp) ?? landlordPhone;
    final caretakerPhone = digits(c.caretakerPhone);
    final managementPhone = digits(c.managementPhone);
    final hasCaretaker =
        caretakerPhone != null || (c.caretakerName?.trim().isNotEmpty ?? false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: KhejaColors.emerald.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(KhejaRadius.md),
            border: Border.all(color: KhejaColors.emerald.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_open_rounded, size: 16, color: KhejaColors.emerald),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  c.unlockedUntil == null
                      ? 'Unlocked'
                      : 'Unlocked until ${DateFormat('h:mm a').format(c.unlockedUntil!)} · '
                          '${_timeLeft(c.unlockedUntil!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: KhejaColors.emerald,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Where exactly — part of what the unlock buys.
        if ((c.addressLine?.trim().isNotEmpty ?? false) ||
            (c.buildingName?.trim().isNotEmpty ?? false)) ...[
          _ExactLocation(address: c.addressLine, building: c.buildingName),
          const SizedBox(height: 12),
        ],

        // The landlord.
        _ContactPerson(
          role: 'LANDLORD',
          name: c.landlordName ?? 'Landlord',
          phone: landlordPhone,
          accent: KhejaColors.blue,
          icon: Icons.person_rounded,
          onCall: landlordPhone == null
              ? null
              : () => _launch(Uri.parse('tel:$landlordPhone'), 'Could not start a call.'),
          onText: landlordPhone == null
              ? null
              : () => _launch(
                    Uri.parse('sms:$landlordPhone'),
                    'Could not open your messages app.',
                  ),
          onWhatsApp: whatsapp == null
              ? null
              : () => _launch(
                    Uri.parse(
                      'https://wa.me/${whatsapp.replaceAll('+', '')}?text='
                      '${Uri.encodeComponent('Hi, I saw "$title" on Kheja_Link. Is it still available?')}',
                    ),
                    'Could not open WhatsApp.',
                  ),
        ),

        // The caretaker, if the landlord gave one.
        if (hasCaretaker) ...[
          const SizedBox(height: 12),
          _ContactPerson(
            role: 'CARETAKER',
            name: c.caretakerName ?? 'Caretaker',
            phone: caretakerPhone,
            accent: KhejaColors.purple,
            icon: Icons.handyman_rounded,
            onCall: caretakerPhone == null
                ? null
                : () => _launch(Uri.parse('tel:$caretakerPhone'), 'Could not start a call.'),
            onText: caretakerPhone == null
                ? null
                : () => _launch(
                      Uri.parse('sms:$caretakerPhone'),
                      'Could not open your messages app.',
                    ),
          ),
        ],

        // Management: the fallback when nobody else picks up.
        if (managementPhone != null) ...[
          const SizedBox(height: 12),
          _ContactPerson(
            role: 'KHEJA_LINK MANAGEMENT',
            name: c.managementName ?? 'Kheja_Link Management',
            phone: managementPhone,
            accent: KhejaColors.emerald,
            icon: Icons.support_agent_rounded,
            note: 'If the landlord or caretaker cannot be reached, call us and we '
                'will connect you.',
            onCall: () =>
                _launch(Uri.parse('tel:$managementPhone'), 'Could not start a call.'),
            onText: () => _launch(
              Uri.parse('sms:$managementPhone'),
              'Could not open your messages app.',
            ),
          ),
        ],

        if (c.hasMap) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _launch(
                Uri.parse(
                  'https://www.google.com/maps/search/?api=1'
                  '&query=${c.latitude},${c.longitude}',
                ),
                'Could not open Maps.',
              ),
              icon: const Icon(Icons.map_rounded, size: 20),
              label: const Text('Open exact location in Maps'),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Locked
  // ---------------------------------------------------------------------------
  Widget _locked(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            KhejaColors.blue.withValues(alpha: 0.10),
            KhejaColors.purple.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: KhejaColors.blue.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: KhejaColors.blue,
                  borderRadius: BorderRadius.circular(KhejaRadius.md),
                ),
                child: const Icon(Icons.lock_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contact & exact location',
                        style: theme.textTheme.titleMedium),
                    Text(
                      'Landlord, caretaker, exact address and Google Maps pin',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: KhejaColors.zinc500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // The blurred teaser, so it is obvious what is behind the wall.
          const _BlurredNumber(),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : _startUnlock,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.lock_open_rounded, size: 20),
              label: Text(_busy
                  ? 'Starting…'
                  : 'Unlock contact'),
            ),
          ),

          if (_awaitingReturn) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _recheck,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('I have paid — check again'),
              ),
            ),
          ],

          const SizedBox(height: 12),
          Text(
            'The landlord\'s and caretaker\'s numbers, the exact address and the map pin '
            'open for ${_settings.unlockHours} hours. Not part of your rent or deposit.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: KhejaColors.zinc500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// The street and building, shown only once the listing is unlocked.
class _ExactLocation extends StatelessWidget {
  const _ExactLocation({this.address, this.building});

  final String? address;
  final String? building;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = [
      if (building?.trim().isNotEmpty ?? false) building!.trim(),
      if (address?.trim().isNotEmpty ?? false) address!.trim(),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        border: Border.all(color: KhejaColors.blue.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.pin_drop_rounded, color: KhejaColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('EXACT LOCATION', style: kEyebrowStyle.copyWith(color: KhejaColors.blue)),
                const SizedBox(height: 4),
                SelectableText(
                  lines.join('\n'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A convincing but fake number behind a blur, so the value of unlocking is
/// obvious. No real digits are ever sent to the client while locked.
class _BlurredNumber extends StatelessWidget {
  const _BlurredNumber();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.md),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          const Icon(Icons.phone_rounded, size: 18, color: KhejaColors.zinc400),
          const SizedBox(width: 12),
          Expanded(
            child: ImageFiltered(
              imageFilter: ColorFilter.mode(Colors.transparent, BlendMode.dst),
              child: Text(
                '+254 7•• ••• •••',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
          const Icon(Icons.lock_rounded, size: 16, color: KhejaColors.zinc400),
        ],
      ),
    );
  }
}

/// One person a tenant can reach once they have unlocked the listing.
class _ContactPerson extends StatelessWidget {
  const _ContactPerson({
    required this.role,
    required this.name,
    required this.phone,
    required this.accent,
    required this.icon,
    this.note,
    this.onCall,
    this.onText,
    this.onWhatsApp,
  });

  final String role;
  final String name;
  final String? phone;
  final Color accent;
  final IconData icon;
  final String? note;
  final VoidCallback? onCall;
  final VoidCallback? onText;
  final VoidCallback? onWhatsApp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(KhejaRadius.md),
                ),
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role, style: kEyebrowStyle.copyWith(color: accent)),
                    const SizedBox(height: 2),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (phone != null)
                      SelectableText(
                        phone!,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      )
                    else
                      const Text(
                        'No number given',
                        style: TextStyle(fontSize: 13, color: KhejaColors.zinc400),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 10),
            Text(
              note!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KhejaColors.zinc500,
                height: 1.45,
              ),
            ),
          ],
          if (onCall != null || onText != null || onWhatsApp != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onCall != null)
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.phone_rounded,
                      label: 'Call',
                      color: accent,
                      filled: true,
                      onTap: onCall!,
                    ),
                  ),
                if (onText != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.sms_rounded,
                      label: 'Text',
                      color: accent,
                      onTap: onText!,
                    ),
                  ),
                ],
                if (onWhatsApp != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.chat_rounded,
                      label: 'WhatsApp',
                      color: KhejaColors.emerald,
                      onTap: onWhatsApp!,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(KhejaRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.sm),
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: filled ? Colors.white : color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: filled ? Colors.white : color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
