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
/// Each company shows its own logo, fetched from its own site and hosted in
/// our storage. Where no usable logo exists the tile falls back to the
/// company's initials in its brand colour. None of these companies is a
/// Kheja_Link partner, and the disclaimer under the rails says so.
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
          _Rail(items: s.items),
          const SizedBox(height: 26),
        ],
        Text(
          'Movement is our own service. The other companies are independent '
          'businesses listed for your convenience — Kheja_Link is not affiliated '
          'with them, takes no commission, and is not responsible for their '
          'service. Logos belong to their owners.',
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

  Future<void> _open(BuildContext context) async {
    final target = partner.url ??
        (partner.phone != null ? 'tel:${partner.phone}' : null);

    if (target == null) {
      showKhejaSnack(
        context,
        '${partner.name} has not shared contact details yet.',
      );
      return;
    }

    final ok = await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showKhejaSnack(context, 'Could not open ${partner.name}.', isError: true);
    }
  }

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
                child: partner.logoUrl != null
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
              'OURS',
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
