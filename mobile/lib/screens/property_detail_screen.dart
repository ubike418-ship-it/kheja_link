import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'inquiry_sheet.dart';

/// The full listing: photo gallery, key facts, description, amenities,
/// location, the landlord's contact options and similar homes.
class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  Property? _property;
  List<Property> _similar = const [];
  bool _isLoading = true;
  String? _error;
  int _imageIndex = 0;
  late final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final property = await khejaApi.fetchPropertyBySlug(widget.slug);
      if (!mounted) return;

      if (property == null) {
        setState(() {
          _isLoading = false;
          _error = 'This home is no longer listed.';
        });
        return;
      }

      setState(() {
        _property = property;
        _isLoading = false;
      });

      // Fire-and-forget; neither should block the page.
      unawaited(khejaApi.recordView(property.id));
      final similar = await khejaApi.fetchSimilar(property);
      if (mounted) setState(() => _similar = similar);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final property = _property;
    if (property == null) return;
    try {
      final saved = await khejaApi.toggleFavorite(property.id);
      if (!mounted) return;
      setState(() => property.isFavorited = saved);
      showKhejaSnack(
          context, saved ? 'Saved to your list.' : 'Removed from your saved homes.');
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _launch(Uri uri, String failureMessage) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showKhejaSnack(context, failureMessage, isError: true);
    }
  }

  String? _digits(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    return cleaned.replaceAll(RegExp(r'\D'), '').length >= 7 ? cleaned : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: PropertyCardSkeleton(imageHeight: 280),
        ),
      );
    }

    if (_error != null || _property == null) {
      return Scaffold(
        appBar: AppBar(),
        body: KhejaErrorState(message: _error ?? 'Not found', onRetry: _load),
      );
    }

    final property = _property!;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _GallerySliver(
            property: property,
            pageController: _pageController,
            imageIndex: _imageIndex,
            onPageChanged: (index) => setState(() => _imageIndex = index),
            onToggleFavorite: _toggleFavorite,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Badges(property: property),
                  const SizedBox(height: 16),
                  Text(property.title,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          size: 18, color: KhejaColors.blue),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          property.addressLine ?? property.locationLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: KhejaColors.zinc500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _RentCard(property: property),
                  const SizedBox(height: 26),
                  _Facts(property: property),

                  if (property.description != null &&
                      property.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 34),
                    Text('About this home',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Text(
                      property.description!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: KhejaColors.zinc500,
                            height: 1.6,
                          ),
                    ),
                  ],

                  if (property.amenities.isNotEmpty) ...[
                    const SizedBox(height: 34),
                    Text("What's included",
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: property.amenities
                          .map((a) => _AmenityChip(label: a.name))
                          .toList(),
                    ),
                  ],

                  const SizedBox(height: 34),
                  _LocationCard(
                    property: property,
                    onOpenMap: (uri) =>
                        _launch(uri, 'Could not open Maps on this device.'),
                  ),

                  const SizedBox(height: 34),
                  _LandlordCard(property: property),

                  const SizedBox(height: 20),
                  _ContactActions(
                    phone: _digits(property.contactPhone),
                    whatsapp: _digits(property.contactWhatsapp ?? property.contactPhone),
                    title: property.title,
                    onLaunch: _launch,
                    onMessage: () => _openInquiry(property),
                  ),

                  const SizedBox(height: 18),
                  const _SafetyNote(),

                  if (_similar.isNotEmpty) ...[
                    const SizedBox(height: 40),
                    Text('You might also like',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 18),
                    ..._similar.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: PropertyCard(
                          property: item,
                          imageHeight: 200,
                          onTap: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => PropertyDetailScreen(slug: item.slug),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInquiry(Property property) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => InquirySheet(property: property),
    );
    if (sent == true && mounted) {
      showKhejaSnack(context, 'Message sent. The landlord will get back to you.');
    }
  }
}

class _GallerySliver extends StatelessWidget {
  const _GallerySliver({
    required this.property,
    required this.pageController,
    required this.imageIndex,
    required this.onPageChanged,
    required this.onToggleFavorite,
  });

  final Property property;
  final PageController pageController;
  final int imageIndex;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final images = property.images;

    return SliverAppBar(
      expandedHeight: 320,
      pinned: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: _RoundIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Back',
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: _RoundIconButton(
            icon: property.isFavorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: property.isFavorited ? KhejaColors.red : null,
            onPressed: onToggleFavorite,
            tooltip: property.isFavorited ? 'Remove from saved' : 'Save this home',
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (images.isEmpty)
              const PropertyImageView(url: null)
            else
              PageView.builder(
                controller: pageController,
                onPageChanged: onPageChanged,
                itemCount: images.length,
                itemBuilder: (_, index) =>
                    PropertyImageView(url: images[index].url),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black38, Colors.transparent],
                  stops: [0, 0.35],
                ),
              ),
            ),
            if (images.length > 1)
              Positioned(
                bottom: 16,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(KhejaRadius.sm),
                  ),
                  child: Text(
                    '${imageIndex + 1} / ${images.length}',
                    style: kEyebrowStyle.copyWith(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, color: color ?? Colors.white, size: 21),
      ),
    );
  }
}

class _Badges extends StatelessWidget {
  const _Badges({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget badge(String label, Color background, Color foreground) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(KhejaRadius.sm),
          ),
          child: Text(label.toUpperCase(),
              style: kEyebrowStyle.copyWith(color: foreground)),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        badge(property.typeName, theme.colorScheme.onSurface,
            theme.colorScheme.surface),
        if (property.isPremium) badge('Premium', KhejaColors.amber, Colors.white),
        if (property.isFurnished)
          badge('Furnished', KhejaColors.emerald, Colors.white),
      ],
    );
  }
}

class _RentCard extends StatelessWidget {
  const _RentCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                property.pricePeriod == 'year' ? 'ANNUAL RENT' : 'MONTHLY RENT',
                style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
              ),
              const SizedBox(height: 6),
              Text(property.priceLabel, style: theme.textTheme.headlineMedium),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('DEPOSIT',
                  style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
              const SizedBox(height: 6),
              Text(
                '${property.depositMonths} '
                '${property.depositMonths == 1 ? 'month' : 'months'}',
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Facts extends StatelessWidget {
  const _Facts({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final size = property.sizeLabel;

    final facts = <({IconData icon, String label, String value})>[
      if (property.bedrooms > 0)
        (
          icon: Icons.king_bed_rounded,
          label: 'Bedrooms',
          value: '${property.bedrooms}'
        ),
      if (property.bathrooms > 0)
        (
          icon: Icons.bathtub_rounded,
          label: 'Bathrooms',
          value: '${property.bathrooms}'
        ),
      if (size != null)
        (icon: Icons.square_foot_rounded, label: 'Size', value: size),
      if (property.availableFrom != null)
        (
          icon: Icons.event_available_rounded,
          label: 'Available',
          value: DateFormat('d MMM y').format(property.availableFrom!)
        ),
      (
        icon: Icons.visibility_rounded,
        label: 'Views',
        value: '${property.viewCount}'
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: facts.map((fact) {
        return Container(
          width: (MediaQuery.of(context).size.width - 40 - 12) / 2,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(KhejaRadius.lg),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(fact.icon, size: 20, color: KhejaColors.blue),
              const SizedBox(height: 12),
              Text(fact.label.toUpperCase(),
                  style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
              const SizedBox(height: 4),
              Text(fact.value,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AmenityChip extends StatelessWidget {
  const _AmenityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.md),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 16, color: KhejaColors.blue),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.property, required this.onOpenMap});

  final Property property;
  final void Function(Uri) onOpenMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = property.location;
    final lat = location?.latitude;
    final lng = location?.longitude;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Location', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
            border: Border.all(color: theme.colorScheme.outline),
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
                      color: KhejaColors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(KhejaRadius.md),
                    ),
                    child: const Icon(Icons.place_rounded,
                        color: KhejaColors.blue, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(location?.name ?? 'Meru',
                            style: theme.textTheme.titleMedium),
                        Text(
                          [location?.area, location?.county]
                              .whereType<String>()
                              .join(', '),
                          style: const TextStyle(
                            color: KhejaColors.zinc500,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (lat != null && lng != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => onOpenMap(
                    Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
                  ),
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text('Open in Google Maps'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LandlordCard extends StatelessWidget {
  const _LandlordCard({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owner = property.owner;
    final name = owner?.fullName ?? 'Kheja_Link Landlord';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: KhejaColors.blue,
              borderRadius: BorderRadius.circular(KhejaRadius.md),
            ),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'K',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (owner?.isVerified ?? false) ...[
                      const Icon(Icons.verified_rounded,
                          size: 14, color: KhejaColors.emerald),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      (owner?.isVerified ?? false)
                          ? 'VERIFIED LANDLORD'
                          : 'LANDLORD',
                      style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (property.publishedAt != null)
            Text(
              formatRelativeDate(property.publishedAt),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: KhejaColors.zinc400,
              ),
            ),
        ],
      ),
    );
  }
}

class _ContactActions extends StatelessWidget {
  const _ContactActions({
    required this.phone,
    required this.whatsapp,
    required this.title,
    required this.onLaunch,
    required this.onMessage,
  });

  final String? phone;
  final String? whatsapp;
  final String title;
  final Future<void> Function(Uri, String) onLaunch;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (phone != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => onLaunch(
                Uri.parse('tel:$phone'),
                'Could not start a call on this device.',
              ),
              icon: const Icon(Icons.phone_rounded, size: 20),
              label: const Text('Call landlord'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.onSurface,
                foregroundColor: Theme.of(context).colorScheme.surface,
              ),
            ),
          ),
        if (whatsapp != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                final digits = whatsapp!.replaceAll(RegExp(r'\D'), '');
                final text = Uri.encodeComponent(
                  'Hi, I saw "$title" on Kheja_Link. Is it still available?',
                );
                onLaunch(
                  Uri.parse('https://wa.me/$digits?text=$text'),
                  'Could not open WhatsApp on this device.',
                );
              },
              icon: const Icon(Icons.chat_rounded, size: 20),
              label: const Text('WhatsApp'),
              style: FilledButton.styleFrom(backgroundColor: KhejaColors.emerald),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.mail_outline_rounded, size: 20),
            label: const Text('Send a message'),
          ),
        ),
      ],
    );
  }
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, size: 16, color: KhejaColors.zinc400),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Never send a deposit before viewing a house in person.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: KhejaColors.zinc400,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
