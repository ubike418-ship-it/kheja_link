import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../models/models.dart';
import 'states.dart';

/// The movers / internet / cleaning rails that sit under a listing.
///
/// Each rail scrolls horizontally and is sized so roughly three tiles are
/// visible at once, with the fourth peeking to signal there is more.
///
/// Only providers the Kheja_Link team has onboarded and approved come back
/// from the database (partners, 0012) — today that is MoveMate Kenya, our
/// moving partner. A section with a single provider shows one full-width card
/// rather than a lonely rail. Logos come bundled with the app where we have
/// them, otherwise from storage, otherwise the company's initials.
class PartnerRails extends StatelessWidget {
  const PartnerRails({super.key, required this.partners});

  final List<Partner> partners;

  static const _sections = <({String category, String title, String blurb})>[
    (
      category: 'movers',
      title: 'Need a mover?',
      blurb: 'Get your things there without the stress',
    ),
    (
      category: 'isp',
      title: 'Get connected',
      blurb: 'Home internet, sorted before you move in',
    ),
    (
      category: 'cleaning',
      title: 'Move-in cleaning',
      blurb: 'Walk into a place that is actually clean',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (partners.isEmpty) return const SizedBox.shrink();

    final sections = _sections
        .map((s) => (
              section: s,
              items: partners.where((p) => p.category == s.category).toList(),
            ))
        .where((s) => s.items.isNotEmpty)
        .toList();

    if (sections.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in sections) ...[
          _RailHeader(title: s.section.title, blurb: s.section.blurb),
          const SizedBox(height: 12),
          if (s.items.length == 1)
            _ProviderCard(partner: s.items.single)
          else
            _Rail(items: s.items),
          const SizedBox(height: 26),
        ],
        Text(
          partners.every((p) => p.isOurs)
              ? '${partners.map((p) => p.name).join(', ')} '
                  '${partners.length == 1 ? 'is a Kheja_Link partner' : 'are Kheja_Link partners'}. '
                  'Their prices are agreed with them directly and are separate from '
                  'your rent and any listing unlock.'
              : 'Partners are marked. Other companies are independent businesses '
                  'listed for your convenience — Kheja_Link is not responsible for '
                  'their service. Logos belong to their owners.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: KhejaColors.zinc400,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.title, required this.blurb});

  final String title;
  final String blurb;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(
          blurb,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: KhejaColors.zinc500,
          ),
        ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.items});

  final List<Partner> items;

  @override
  Widget build(BuildContext context) {
    // Three across, with the next one just showing at the edge.
    final width = (MediaQuery.of(context).size.width - 40 - 24) / 3.25;

    return SizedBox(
      height: width + 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) =>
            _PartnerTile(partner: items[index], width: width),
      ),
    );
  }
}

class _PartnerTile extends StatelessWidget {
  const _PartnerTile({required this.partner, required this.width});

  final Partner partner;
  final double width;

  Future<void> _open(BuildContext context) => _contactPartner(context, partner);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = Color(partner.colorValue);

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(KhejaRadius.lg),
            child: InkWell(
              onTap: () => _open(context),
              borderRadius: BorderRadius.circular(KhejaRadius.lg),
              child: Container(
                width: width,
                height: width,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(KhejaRadius.lg),
                  border: Border.all(
                    color: partner.isOurs
                        ? brand.withValues(alpha: 0.55)
                        : theme.colorScheme.outline,
                    width: partner.isOurs ? 1.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: partner.bundledLogoAsset != null
                    ? ColoredBox(
                        color: Colors.white,
                        child: Padding(
                          padding: EdgeInsets.all(width * 0.06),
                          child: Image.asset(partner.bundledLogoAsset!, fit: BoxFit.contain),
                        ),
                      )
                    : partner.logoUrl != null
                    // Real logos sit on white with breathing room, like an app
                    // icon. Several companies only publish a small icon, and
                    // stretching one edge to edge would leave it blurred.
                    ? ColoredBox(
                        color: Colors.white,
                        child: Padding(
                          padding: EdgeInsets.all(width * 0.18),
                          child: CachedNetworkImage(
                            imageUrl: partner.logoUrl!,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            placeholder: (_, __) => const SizedBox.shrink(),
                            errorWidget: (_, __, ___) => _initialsTile(brand),
                          ),
                        ),
                      )
                    : _initialsTile(brand),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            partner.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
          if (partner.isOurs)
            Text(
              'PARTNER',
              style: kEyebrowStyle.copyWith(color: brand, fontSize: 8),
            ),
        ],
      ),
    );
  }

  /// The stand-in for a logo: initials on the company's brand colour.
  Widget _initialsTile(Color brand) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            brand.withValues(alpha: 0.16),
            brand.withValues(alpha: 0.06),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              partner.initials,
              style: TextStyle(
                fontSize: width * 0.30,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: brand,
              ),
            ),
            Icon(_iconFor(partner.category), size: width * 0.16, color: brand),
          ],
        ),
      ),
    );
  }

  static IconData _iconFor(String category) => switch (category) {
        'movers' => Icons.local_shipping_rounded,
        'isp' => Icons.wifi_rounded,
        'cleaning' => Icons.cleaning_services_rounded,
        _ => Icons.storefront_rounded,
      };
}

Future<void> _contactPartner(BuildContext context, Partner partner, {bool call = false}) async {
  final phone = partner.phone;
  final target = call && phone != null
      ? 'tel:$phone'
      : partner.url ?? (phone != null ? 'tel:$phone' : null);

  if (target == null) {
    showKhejaSnack(context, '${partner.name} has not shared contact details yet.');
    return;
  }

  final ok = await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showKhejaSnack(context, 'Could not open ${partner.name}.', isError: true);
  }
}

/// A section with one provider: a full-width card with the logo big enough to
/// read, and a direct call button.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.partner});

  final Partner partner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = Color(partner.colorValue);

    final Widget logo;
    if (partner.bundledLogoAsset != null) {
      logo = Image.asset(partner.bundledLogoAsset!, fit: BoxFit.contain);
    } else if (partner.logoUrl != null) {
      logo = CachedNetworkImage(
        imageUrl: partner.logoUrl!,
        fit: BoxFit.contain,
        errorWidget: (_, __, ___) => Icon(Icons.local_shipping_rounded, color: brand),
      );
    } else {
      logo = Center(
        child: Text(
          partner.initials,
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: brand),
        ),
      );
    }

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.xl),
      child: InkWell(
        onTap: () => _contactPartner(context, partner),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
            border: Border.all(
              color: partner.isOurs ? brand.withValues(alpha: 0.5) : theme.colorScheme.outline,
              width: partner.isOurs ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 84,
                height: 84,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(KhejaRadius.md),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                clipBehavior: Clip.antiAlias,
                child: logo,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (partner.isOurs)
                      Text('KHEJA_LINK PARTNER',
                          style: kEyebrowStyle.copyWith(color: brand, fontSize: 9)),
                    const SizedBox(height: 2),
                    Text(
                      partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (partner.tagline != null)
                      Text(
                        partner.tagline!,
                        maxLines: 2,
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
              if (partner.phone != null)
                IconButton.filled(
                  onPressed: () => _contactPartner(context, partner, call: true),
                  style: IconButton.styleFrom(backgroundColor: brand),
                  tooltip: 'Call ${partner.name}',
                  icon: const Icon(Icons.call_rounded, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
