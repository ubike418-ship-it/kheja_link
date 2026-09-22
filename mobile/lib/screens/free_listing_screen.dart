import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../widgets/brand.dart';

/// The last screen of the landlord tutorial: listing is free for now.
///
/// Reads the fee and the offer wording from app_settings, so when a listing
/// fee is introduced this screen changes with it — no new build. An end date
/// is only shown if one has actually been configured.
class FreeListingScreen extends StatefulWidget {
  const FreeListingScreen({super.key});

  @override
  State<FreeListingScreen> createState() => _FreeListingScreenState();
}

class _FreeListingScreenState extends State<FreeListingScreen> {
  BusinessSettings _settings = const BusinessSettings();

  @override
  void initState() {
    super.initState();
    khejaApi.cachedBusinessSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
    khejaApi.fetchBusinessSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final free = _settings.listingIsFree;
    final endsOn = _settings.listingOfferEndsOn;

    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          const Eyebrow('For landlords', icon: Icons.vpn_key_rounded, color: KhejaColors.emerald),
          const SizedBox(height: 10),
          Text(
            free ? 'List your property for free.' : 'List your property.',
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 10),
          Text(
            'Put your homes in front of tenants across Meru, and manage requests and '
            'availability from one place.',
            style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500, height: 1.5),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [KhejaColors.emerald, Color(0xFF047857)],
              ),
              borderRadius: BorderRadius.circular(KhejaRadius.xl),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LISTING FEE',
                    style: kEyebrowStyle.copyWith(color: Colors.white.withValues(alpha: 0.8))),
                const SizedBox(height: 6),
                Text(
                  free ? 'KSh 0' : formatPrice(_settings.landlordListingFee),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.6,
                  ),
                ),
                if (free) ...[
                  const SizedBox(height: 4),
                  Text(
                    _settings.listingOfferLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  if (endsOn != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Offer ends ${formatShortDate(endsOn)}.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          for (final (icon, text) in const [
            (Icons.add_a_photo_rounded, 'Add photos, a video tour and the details tenants ask about.'),
            (Icons.event_available_rounded, 'Mark a home occupied and set the date it frees up — tenants can ask to be told.'),
            (Icons.inbox_rounded, 'See tenant requests and interested tenants, and accept or decline.'),
            (Icons.notifications_active_rounded, 'Get notified about new requests and interest.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: KhejaColors.emerald),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(text,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.45)),
                  ),
                ],
              ),
            ),
          if (free) ...[
            const SizedBox(height: 6),
            const Text(
              'If a listing fee is introduced, you will be told in the app before it '
              'applies to you.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KhejaColors.zinc400, height: 1.5),
            ),
          ],
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: KhejaColors.emerald,
                minimumSize: const Size.fromHeight(58),
              ),
              child: const Text('Continue to my dashboard'),
            ),
          ),
        ],
      ),
    );
  }
}
