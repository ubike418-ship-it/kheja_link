import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../widgets/brand.dart';

/// Short stays, announced but not built.
///
/// Kheja_Link is deliberately a long-term rentals product, so this page exists
/// to say "we know, it is coming" rather than to hint at something that works.
/// Nothing here pretends to be functional.
class AirbnbSoonScreen extends StatelessWidget {
  const AirbnbSoonScreen({super.key, this.isRoot = true});

  final bool isRoot;

  static const _plans = <({IconData icon, String title, String body})>[
    (
      icon: Icons.nightlight_round,
      title: 'Nightly and weekly stays',
      body: 'Furnished places for a night, a weekend or a month — priced by the '
          'night rather than by the month.',
    ),
    (
      icon: Icons.event_available_rounded,
      title: 'Real availability calendars',
      body: 'See exactly which dates are free before you message anyone.',
    ),
    (
      icon: Icons.verified_user_rounded,
      title: 'Verified hosts and reviews',
      body: 'Ratings from people who actually stayed, so you know what you are '
          'walking into.',
    ),
    (
      icon: Icons.lock_clock_rounded,
      title: 'Instant booking',
      body: 'Reserve and pay in the app, with the host confirming in minutes.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !isRoot,
        title: const Text('Short stays'),
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
                  'Short stays are\non the way.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 14),
                Text(
                  'Kheja_Link does long-term rentals properly first. Furnished '
                  'nightly and weekly stays across Meru are next.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: KhejaColors.zinc500, height: 1.55),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),

          Text('What we are building',
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

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: KhejaColors.blue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(KhejaRadius.xl),
              border: Border.all(color: KhejaColors.blue.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded, size: 20, color: KhejaColors.blue),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Have a furnished place you would let by the night? Email '
                    'hello@khejalink.name.ng and we will bring you in early.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      height: 1.5,
                    ),
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
