import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../services/payments.dart';
import '../widgets/brand.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';
import 'auth_screen.dart';
import 'payment_sheet.dart';

/// The KES 500 house hunting fee: what it is, what it is not, and paying it.
///
/// Also the last screen of the tenant tutorial ([isOnboarding]), where it
/// ends in "Continue" rather than being a page you navigate back from.
///
/// Paying happens in Kheja_Link's own payment screen ([PaymentSheet]). The fee
/// is only ever marked paid after the server hears it from Paystack, so this
/// screen only ever reflects a status it was given.
class HuntingScreen extends StatefulWidget {
  const HuntingScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  State<HuntingScreen> createState() => _HuntingScreenState();
}

class _HuntingScreenState extends State<HuntingScreen> with WidgetsBindingObserver {
  BusinessSettings _settings = const BusinessSettings();
  HuntingService _service = HuntingService.none;
  bool _loading = true;
  bool _paying = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Show the cached price at once, so this renders with no data.
    khejaApi.cachedBusinessSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from a card page: see whether the payment has landed.
    if (state == AppLifecycleState.resumed && _service.isPending) _load(quiet: true);
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final settings = await khejaApi.fetchBusinessSettings();
    HuntingService service = _service;
    String? error;
    try {
      service = await khejaApi.fetchHuntingService();
    } catch (e) {
      error = describeError(e);
    }
    if (!mounted) return;
    final justActivated = !_service.isActive && service.isActive;
    setState(() {
      _settings = settings;
      _service = service;
      _loading = false;
      _loadError = khejaApi.isSignedIn ? error : null;
    });
    if (justActivated) {
      showKhejaSnack(context, 'Payment received. Your House Hunting service is active.');
    }
  }

  Future<void> _pay() async {
    if (!khejaApi.isSignedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen(role: 'seeker')),
      );
      if (!mounted || !khejaApi.isSignedIn) return;
      await _load(quiet: true);
      if (_service.isActive || !mounted) return;
    }

    setState(() => _paying = true);

    // The database creates the pending payment and prices it; the app never
    // sends an amount.
    final ({String reference, num amount, String currency})? started;
    try {
      started = await khejaApi.startHuntingPayment();
    } catch (error) {
      if (!mounted) return;
      setState(() => _paying = false);
      showKhejaSnack(context, describeError(error), isError: true);
      return;
    }
    if (!mounted) return;
    setState(() => _paying = false);

    if (started == null) {
      showKhejaSnack(context, 'Your House Hunting service is already active.');
      await _load(quiet: true);
      return;
    }

    final paid = await showKhejaSheet<bool>(
      context,
      PaymentSheet(
        reference: started.reference,
        amountLabel: formatPrice(started.amount, started.currency),
        title: 'House hunting fee',
        what: 'Kheja_Link house hunting service — separate from rent and deposit.',
        cardCheckoutUrl: () => KhejaCheckout.cardCheckoutUrl(started!.reference),
      ),
    );

    if (!mounted) return;
    await _load(quiet: true);
    if (paid == true && mounted) {
      showKhejaSnack(context, 'Payment received. Your House Hunting service is active.');
    }
  }

  Future<void> _checkAgain() async {
    await _load(quiet: true);
    if (!mounted || _service.isActive) return;
    showKhejaSnack(
      context,
      'No payment confirmed yet. If you have just paid, give it a minute and check again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = _settings.huntingFeeLabel;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isOnboarding,
        title: widget.isOnboarding ? null : const Text('House Hunting'),
      ),
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: () => _load(quiet: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Eyebrow('House hunting service', icon: Icons.travel_explore_rounded),
            const SizedBox(height: 10),
            Text(
              widget.isOnboarding ? 'Find your next home with Kheja_Link.' : 'House Hunting',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Pay the house hunting fee, tell us what you are looking for, and discover '
              'suitable homes available through Kheja_Link.',
              style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500, height: 1.5),
            ),
            const SizedBox(height: 22),

            _FeeCard(fee: fee, service: _service, signedIn: khejaApi.isSignedIn),
            const SizedBox(height: 22),

            Text('What the fee is for', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _Point(
              icon: Icons.handshake_rounded,
              color: KhejaColors.blue,
              text: 'Kheja_Link\'s house hunting service: we help connect you with a '
                  'suitable home that is available through Kheja_Link.',
            ),
            if (_settings.huntingUnlocksContacts)
              _Point(
                icon: Icons.lock_open_rounded,
                color: KhejaColors.emerald,
                text: 'While your service is active, the landlord\'s and caretaker\'s '
                    'numbers and the exact location are unlocked on every listing — '
                    'no separate ${formatPrice(_settings.contactUnlockFee)} unlocks.',
              ),
            _Point(
              icon: Icons.key_rounded,
              color: KhejaColors.purple,
              text: 'Once you are connected with a home, you rent it directly from the '
                  'landlord through the normal rental process.',
            ),
            const SizedBox(height: 18),

            _NotIncluded(fee: fee),
            const SizedBox(height: 18),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: KhejaColors.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(KhejaRadius.lg),
                border: Border.all(color: KhejaColors.amber.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Kheja_Link cannot guarantee a particular house: which homes are free '
                'depends on landlords. You pay once; paying again is blocked while your '
                'service is active.',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: KhejaColors.zinc500,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 26),

            if (_loadError != null) ...[
              Text(
                _loadError!,
                style: const TextStyle(color: KhejaColors.red, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
            ],

            if (_service.isActive)
              _ActiveBanner(service: _service)
            else ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: (_paying || _loading) ? null : _pay,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
                  icon: _paying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.lock_rounded, size: 20),
                  label: Text(
                    _paying
                        ? 'Opening secure checkout…'
                        : khejaApi.isSignedIn
                            ? 'Pay $fee hunting fee'
                            : 'Sign in to pay $fee',
                  ),
                ),
              ),
              if (_service.isPending) ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _paying ? null : _checkAgain,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('I have paid — check again'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'You pay on Paystack\'s secure checkout page. Your payment is confirmed '
                'by Paystack directly — not by this app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: KhejaColors.zinc400,
                  height: 1.5,
                ),
              ),
            ],

            if (widget.isOnboarding) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: _service.isActive
                    ? FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Continue'),
                      )
                    : OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Continue — I will decide later'),
                      ),
              ),
              const SizedBox(height: 14),
              const Text(
                'This guide works without data. Searching, payments, requests and '
                'alerts need an internet connection.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: KhejaColors.zinc400),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeeCard extends StatelessWidget {
  const _FeeCard({required this.fee, required this.service, required this.signedIn});

  final String fee;
  final HuntingService service;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KhejaColors.blue, KhejaColors.blueDark],
        ),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('HOUSE HUNTING FEE',
              style: kEyebrowStyle.copyWith(color: Colors.white.withValues(alpha: 0.75))),
          const SizedBox(height: 6),
          Text(
            fee,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'One-off · paid to Kheja_Link · not rent',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (signedIn) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    service.isActive ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'STATUS: ${service.label.toUpperCase()}',
                    style: kEyebrowStyle.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Makes it impossible to mistake the hunting fee for rent.
class _NotIncluded extends StatelessWidget {
  const _NotIncluded({required this.fee});

  final String fee;

  static const _items = [
    (Icons.home_rounded, 'Monthly rent'),
    (Icons.account_balance_wallet_rounded, 'Deposit'),
    (Icons.receipt_long_rounded, 'Landlord charges (water, service charge)'),
    (Icons.local_shipping_rounded, 'Moving costs'),
    (Icons.cleaning_services_rounded, 'Cleaning costs'),
    (Icons.storefront_rounded, 'Other third-party services'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NOT PART OF THE $fee', style: kEyebrowStyle.copyWith(color: KhejaColors.red)),
          const SizedBox(height: 6),
          Text(
            'These are paid separately, directly to the landlord or the service provider:',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: KhejaColors.zinc500,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final (icon, label) in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: KhejaColors.zinc400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.close_rounded, size: 16, color: KhejaColors.red),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KhejaRadius.sm),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                text,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.45),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveBanner extends StatelessWidget {
  const _ActiveBanner({required this.service});

  final HuntingService service;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KhejaColors.emerald.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: KhejaColors.emerald.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: KhejaColors.emerald),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              service.status == 'matched'
                  ? 'You have been matched with a home. Keep an eye on My Requests.'
                  : 'Your House Hunting service is active'
                      '${service.activatedAt != null ? ' since ${formatShortDate(service.activatedAt!)}' : ''}. '
                      'Browse homes and send requests.',
              style: const TextStyle(fontWeight: FontWeight.w800, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
