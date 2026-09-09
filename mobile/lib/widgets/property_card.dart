import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';
import '../services/network.dart';

/// The listing card, carried over from the web design: tall image, glass
/// badges, the rent overlaid bottom-left, and a stats strip under the title.
class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.property,
    required this.onTap,
    this.onToggleFavorite,
    this.imageHeight = 230,
  });

  final Property property;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.xxl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.xxl),
            border: Border.all(color: scheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Cover(
                property: property,
                height: imageHeight,
                onToggleFavorite: onToggleFavorite,
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 16, color: KhejaColors.blue),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            property.locationLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: KhejaColors.zinc500,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: scheme.outline, height: 1),
                    const SizedBox(height: 16),
                    _Stats(property: property),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.property,
    required this.height,
    this.onToggleFavorite,
  });

  final Property property;
  final double height;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PropertyImageView(url: property.coverUrl, width: 720),

          // Scrim, so the white badges and price stay legible on any photo.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black26, Colors.transparent, Colors.black87],
                stops: [0, 0.45, 1],
              ),
            ),
          ),

          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _GlassChip(label: property.typeName.toUpperCase()),
                if (property.isPremium) ...[
                  const SizedBox(width: 8),
                  const _GlassChip(label: 'PREMIUM', background: KhejaColors.amber),
                ],
                const Spacer(),
                if (property.likeCount > 0) ...[
                  _GlassChip(
                    label: '${property.likeCount} '
                        '${property.likeCount == 1 ? "LIKE" : "LIKES"}',
                  ),
                  const SizedBox(width: 8),
                ],
                if (onToggleFavorite != null)
                  _FavoriteButton(
                    isFavorited: property.isFavorited,
                    onPressed: onToggleFavorite!,
                  ),
              ],
            ),
          ),

          Positioned(
            left: 20,
            bottom: 18,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.pricePeriod == 'year' ? 'ANNUAL RENT' : 'MONTHLY RENT',
                  style: kEyebrowStyle.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 2),
                Text(
                  property.priceLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
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

/// Network image with a neutral placeholder and a graceful failure state —
/// a broken photo should never look like a broken app.
class PropertyImageView extends StatelessWidget {
  const PropertyImageView({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.width = 640,
  });

  final String? url;
  final BoxFit fit;

  /// The width actually being drawn. Requesting only this makes the app usable
  /// on mobile data — the seeded photos are 1200px, which is several megabytes
  /// across a full screen of listings.
  final int width;

  @override
  Widget build(BuildContext context) {
    final placeholderColor =
        Theme.of(context).brightness == Brightness.dark
            ? KhejaColors.zinc800
            : KhejaColors.zinc200;

    if (url == null || url!.isEmpty) {
      return Container(
        color: placeholderColor,
        child: const Center(
          child: Icon(Icons.home_work_rounded, size: 40, color: KhejaColors.zinc400),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: sizedImageUrl(url!, width),
      fit: fit,
      // Decode at roughly the drawn size too, which keeps memory down on the
      // cheaper phones this app is mostly used on.
      memCacheWidth: width,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (_, __) => Container(color: placeholderColor),
      errorWidget: (_, __, ___) => Container(
        color: placeholderColor,
        child: const Center(
          child: Icon(Icons.image_not_supported_rounded,
              size: 32, color: KhejaColors.zinc400),
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.label, this.background});

  final String label;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: background ?? Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(KhejaRadius.sm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: kEyebrowStyle.copyWith(color: Colors.white)),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.isFavorited, required this.onPressed});

  final bool isFavorited;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isFavorited ? 'Remove from saved homes' : 'Save this home',
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(KhejaRadius.sm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(KhejaRadius.sm),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KhejaRadius.sm),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Icon(
              isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: 20,
              color: isFavorited ? KhejaColors.red : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final size = property.sizeLabel;

    final items = <Widget>[
      if (property.bedrooms > 0)
        _StatChip(
          icon: Icons.king_bed_rounded,
          value: '${property.bedrooms}',
          color: KhejaColors.blue,
        ),
      if (property.bathrooms > 0)
        _StatChip(
          icon: Icons.bathtub_rounded,
          value: '${property.bathrooms}',
          color: KhejaColors.emerald,
        ),
      if (size != null)
        _StatChip(icon: Icons.square_foot_rounded, value: size, color: KhejaColors.purple),
    ];

    if (items.isEmpty) {
      return Text(
        'Commercial space',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: KhejaColors.zinc500, fontWeight: FontWeight.w800),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: items,
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.value, required this.color});

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(KhejaRadius.sm),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
