import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';
import 'auth_screen.dart';
import 'give_house_sheet.dart';

/// Unlocks & refunds: how unlocking works, what it is not, and giving
/// Kheja_Link a house — with the tenant's own houses and refunds underneath.
///
/// Amounts appear here only for a tenant who has already paid for an unlock.
/// Everyone else first sees the price on the payment screen, when they tap
/// "Unlock contact" on a home they want.
///
/// Nothing is paid on this screen. The unlock is charged on the listing itself,
/// when the tenant taps "Unlock contact". The House Hunting pass that used to
/// be sold here was retired in 0015; a pass bought before then still unlocks
/// every listing and is shown as such.
///
/// Also the last screen of the tenant tutorial ([isOnboarding]), where it
/// ends in "Continue" rather than being a page you navigate back from.
class HuntingScreen extends StatefulWidget {
  const HuntingScreen({super.key, this.isOnboarding = false});

  final bool isOnboarding;

  @override
  State<HuntingScreen> createState() => _HuntingScreenState();
}

class _HuntingScreenState extends State<HuntingScreen> {
  BusinessSettings _settings = const BusinessSettings();
  HuntingService _pass = HuntingService.none;
  List<HouseSubmission> _houses = const [];
  bool _hasPaidUnlock = false;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    // Show the cached prices at once, so this renders with no data.
    khejaApi.cachedBusinessSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
    _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    final settings = await khejaApi.fetchBusinessSettings();
    var pass = _pass;
    var houses = _houses;
    var hasPaid = _hasPaidUnlock;
    String? error;
    if (khejaApi.isSignedIn) {
      try {
        final results = await Future.wait<Object>([
          khejaApi.fetchHuntingService().catchError((_) => HuntingService.none),
          khejaApi.fetchMyHouseSubmissions(),
          khejaApi.fetchUnlockedPropertyIds(),
        ]);
        pass = results[0] as HuntingService;
        houses = results[1] as List<HouseSubmission>;
        hasPaid = (results[2] as Set<String>).isNotEmpty;
      } catch (e) {
        error = describeError(e);
      }
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _pass = pass;
      _houses = houses;
      _hasPaidUnlock = hasPaid;
      _loading = false;
      _loadError = error;
    });
  }

  Future<void> _giveHouse() async {
    if (!khejaApi.isSignedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AuthScreen(role: 'seeker')),
      );
      if (!mounted || !khejaApi.isSignedIn) return;
    }
    if (!mounted) return;
    final sent = await showKhejaSheet<bool>(
      context,
      GiveHouseSheet(settings: _settings, showRefund: _hasPaidUnlock),
    );
    if (sent != true || !mounted) return;
    showKhejaSnack(context, 'House sent. We will tell you in your Inbox how it goes.');
    await _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = _settings.unlockFeeLabel;
    final refund = _settings.refundLabel;
    // Someone who has paid already knows the price; nobody else sees it here.
    final showPrices = _hasPaidUnlock || _pass.isActive;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isOnboarding,
        title: widget.isOnboarding ? null : const Text('Unlocks & refunds'),
      ),
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: () => _load(quiet: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Eyebrow('How pricing works', icon: Icons.lock_open_rounded),
            const SizedBox(height: 10),
            Text(
              widget.isOnboarding ? 'Find your next home with Kheja_Link.' : 'Unlocks & refunds',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 10),
            Text(
              'Browsing, saving homes and messaging Kheja_Link are free. When you find a home '
              'you want, unlock it to get the landlord\'s and caretaker\'s numbers and the '
              'exact location.',
              style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500, height: 1.5),
            ),
            const SizedBox(height: 22),

            if (showPrices) ...[
              _FeeCard(fee: fee, pass: _pass),
              const SizedBox(height: 22),
            ],

            Text('How unlocking works', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _Point(
              icon: Icons.touch_app_rounded,
              color: KhejaColors.blue,
              text: showPrices
                  ? 'Open a listing and tap Unlock contact. You pay $fee by M-Pesa right '
                      'there — nothing is charged before that.'
                  : 'Open a listing and tap Unlock contact. You see the amount and pay by '
                      'M-Pesa right there — nothing is charged before you approve it.',
            ),
            const _Point(
              icon: Icons.verified_user_rounded,
              color: KhejaColors.emerald,
              text: 'Once per listing. The details stay yours, and you are never charged '
                  'twice for the same home.',
            ),
            const _Point(
              icon: Icons.key_rounded,
              color: KhejaColors.purple,
              text: 'You then rent directly from the landlord through the normal rental process.',
            ),
            const SizedBox(height: 18),

            if (_settings.refundsEnabled && showPrices)
              _RefundOffer(fee: fee, refund: refund, onGiveHouse: _giveHouse)
            else
              _GiveHousePlain(onGiveHouse: _giveHouse),
            const SizedBox(height: 18),

            const _NotIncluded(),
            const SizedBox(height: 26),

            if (khejaApi.isSignedIn) ...[
              Text('Your houses & refunds', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (_loadError != null)
                Text(
                  _loadError!,
                  style: const TextStyle(color: KhejaColors.red, fontWeight: FontWeight.w700),
                )
              else if (_loading && _houses.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator(color: KhejaColors.blue)),
                )
              else if (_houses.isEmpty)
                const Text(
                  'Houses you give us, and any refund they earn, appear here.',
                  style: TextStyle(color: KhejaColors.zinc500, fontWeight: FontWeight.w600),
                )
              else
                for (final house in _houses) _HouseTile(house: house),
            ],

            if (widget.isOnboarding) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Continue'),
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
  const _FeeCard({required this.fee, required this.pass});

  final String fee;
  final HuntingService pass;

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
          Text('UNLOCK A LISTING',
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
            'Per listing · same for everyone · paid once · not rent',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w800,
            ),
          ),
          // A House Hunting pass bought before it was retired still covers
          // every listing.
          if (pass.isActive) ...[
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
                  const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'YOUR HOUSE HUNTING PASS UNLOCKS EVERY LISTING',
                      style: kEyebrowStyle.copyWith(color: Colors.white),
                    ),
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

/// "Give us a house" without amounts, for tenants who have not unlocked yet.
class _GiveHousePlain extends StatelessWidget {
  const _GiveHousePlain({required this.onGiveHouse});

  final VoidCallback onGiveHouse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KhejaColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: KhejaColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KNOW A VACANT HOUSE?', style: kEyebrowStyle.copyWith(color: KhejaColors.emerald)),
          const SizedBox(height: 8),
          Text(
            'Moving out, or know a landlord who wants to list? Tell us about the house and we '
            'will check it with the landlord.',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onGiveHouse,
              style: FilledButton.styleFrom(backgroundColor: KhejaColors.emerald),
              icon: const Icon(Icons.add_home_rounded, size: 20),
              label: const Text('Give us a house'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundOffer extends StatelessWidget {
  const _RefundOffer({required this.fee, required this.refund, required this.onGiveHouse});

  final String fee;
  final String refund;
  final VoidCallback onGiveHouse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KhejaColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: KhejaColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('GIVE US A HOUSE, GET $refund BACK',
              style: kEyebrowStyle.copyWith(color: KhejaColors.emerald)),
          const SizedBox(height: 8),
          Text(
            'Paid $fee to unlock a listing? Tell us about a vacant house — the one you are '
            'moving out of, or one whose landlord agrees to list with us. Once we approve it, '
            'we refund $refund. One refund per unlock; without a house, the $fee is not refunded.',
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onGiveHouse,
              style: FilledButton.styleFrom(backgroundColor: KhejaColors.emerald),
              icon: const Icon(Icons.add_home_rounded, size: 20),
              label: const Text('Give us a house'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseTile extends StatelessWidget {
  const _HouseTile({required this.house});

  final HouseSubmission house;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final refund = house.refund;
    final (color, icon) = switch (refund?.status ?? house.status) {
      'paid' => (KhejaColors.emerald, Icons.check_circle_rounded),
      'approved' => (KhejaColors.blue, Icons.hourglass_bottom_rounded),
      'rejected' => (KhejaColors.zinc500, Icons.block_rounded),
      _ => (KhejaColors.amber, Icons.schedule_rounded),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(house.title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  refund == null
                      ? '${house.statusLabel} · no refund applies'
                      : '${house.statusLabel} · ${refund.amountLabel} ${refund.statusLabel.toLowerCase()}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
                ),
                if (refund?.payoutReference != null)
                  Text(
                    'M-Pesa reference ${refund!.payoutReference}',
                    style: const TextStyle(fontSize: 12, color: KhejaColors.zinc500),
                  ),
                if (house.adminNote != null && house.adminNote!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '"${house.adminNote!.trim()}"',
                      style: const TextStyle(fontSize: 12, color: KhejaColors.zinc500),
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

/// Makes it impossible to mistake the unlock for rent.
class _NotIncluded extends StatelessWidget {
  const _NotIncluded();

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
          Text('NOT PART OF AN UNLOCK', style: kEyebrowStyle.copyWith(color: KhejaColors.red)),
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
