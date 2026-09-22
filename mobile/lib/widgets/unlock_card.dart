import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../screens/payment_sheet.dart';
import '../services/payments.dart';
import 'kheja_sheet.dart';
import 'states.dart';

/// The KSh 150 contact unlock.
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
    this.onHuntingFee,
  });

  final Property property;
  final PropertyContact contact;
  final Future<void> Function() onUnlocked;
  final Future<bool> Function() onRequireSignIn;

  /// Opens the house hunting fee, which (when configured) unlocks every
  /// listing at once. Null hides the option.
  final Future<void> Function()? onHuntingFee;

  @override
  State<UnlockCard> createState() => _UnlockCardState();
}

class _UnlockCardState extends State<UnlockCard> {
  bool _busy = false;
  bool _awaitingReturn = false;

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

    // Already paid for (perhaps on another device)? Nothing to buy.
    if (await khejaApi.hasUnlocked(widget.property.id)) {
      if (!mounted) return;
      setState(() => _busy = false);
      await widget.onUnlocked();
      return;
    }

    final String reference;
    try {
      reference = await khejaApi.startContactUnlock(widget.property.id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showKhejaSnack(context, describeError(error), isError: true);
      return;
    }

    if (!mounted) return;
    setState(() => _busy = false);

    final paid = await showKhejaSheet<bool>(
      context,
      PaymentSheet(
        reference: reference,
        amountLabel: formatPrice(kUnlockAmount),
        title: 'Unlock contact details',
        what: 'The landlord, caretaker and exact location for '
            '"${widget.property.title}".',
        cardCheckoutUrl: () => KhejaCheckout.cardCheckoutUrl(reference),
      ),
    );

    if (!mounted) return;
    if (paid == true) {
      showKhejaSnack(context, 'Unlocked. The details are below.');
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
          child: const Row(
            children: [
              Icon(Icons.lock_open_rounded, size: 16, color: KhejaColors.emerald),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Unlocked — these details stay yours for this home.',
                  style: TextStyle(
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
                    Text('Contact the landlord',
                        style: theme.textTheme.titleMedium),
                    Text(
                      'Landlord, caretaker, management line and map pin',
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

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatPrice(kUnlockAmount),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: KhejaColors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: KhejaColors.amber,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text('OFFER',
                      style: kEyebrowStyle.copyWith(color: Colors.white, fontSize: 9)),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'One-off',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: KhejaColors.zinc500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

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
                  : 'Unlock for ${formatPrice(kUnlockAmount)}'),
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

          if (widget.onHuntingFee != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _busy ? null : widget.onHuntingFee,
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Or use the House Hunting service — unlocks every home'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Pays for itself once: unlock this home and the details stay yours. '
            'You can still send a free message without unlocking.',
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
