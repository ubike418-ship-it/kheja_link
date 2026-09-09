import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/property_card.dart';
import '../widgets/partner_rails.dart';
import '../widgets/states.dart';
import '../widgets/unlock_card.dart';
import 'auth_screen.dart';
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
  List<Partner> _partners = const [];
  PropertyContact _contact = PropertyContact.locked;
  Tenancy? _myTenancy;
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

      // Fire-and-forget; this must never block the page.
      unawaited(khejaApi.recordView(property.id));

      // Everything else can arrive after the listing itself is on screen.
      final rest = await Future.wait([
        khejaApi.fetchSimilar(property),
        khejaApi.fetchPropertyContact(property.id),
        khejaApi.fetchPartners(),
        khejaApi.fetchMyTenancyFor(property.id),
      ]);

      if (!mounted) return;
      setState(() {
        _similar = rest[0] as List<Property>;
        _contact = rest[1] as PropertyContact;
        _partners = rest[2] as List<Partner>;
        _myTenancy = rest[3] as Tenancy?;
      });
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

  /// Re-reads the contact after a payment. The database decides whether the
  /// details come back; the app just asks again.
  Future<void> _refreshContact() async {
    final property = _property;
    if (property == null) return;
    final contact = await khejaApi.fetchPropertyContact(property.id);
    if (!mounted) return;
    setState(() => _contact = contact);
  }

  /// Sends the user to sign in, returning whether they came back signed in.
  Future<bool> _requireSignIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
    if (!mounted) return false;
    final signedIn = khejaApi.isSignedIn;
    if (signedIn) await _refreshContact();
    return signedIn;
  }

  Future<void> _book(Property property) async {
    if (!khejaApi.isSignedIn && !await _requireSignIn()) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
        ),
        title: const Text('Book this home?'),
        content: Text(
          'This tells the landlord you intend to move into ${property.title}. '
          'It is not a payment, and it does not replace seeing the house first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Book'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await khejaApi.bookProperty(property.id);
      final tenancy = await khejaApi.fetchMyTenancyFor(property.id);
      if (!mounted) return;
      setState(() => _myTenancy = tenancy);
      showKhejaSnack(context, 'Booked. The landlord has been notified.');
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _setTenancy(String status, String message) async {
    final tenancy = _myTenancy;
    if (tenancy == null) return;
    try {
      await khejaApi.setTenancyStatus(tenancy.id, status);
      final updated = await khejaApi.fetchMyTenancyFor(tenancy.propertyId);
      if (!mounted) return;
      setState(() => _myTenancy = updated);
      showKhejaSnack(context, message);
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
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

                  if (property.houseRules != null &&
                      property.houseRules!.trim().isNotEmpty) ...[
                    const SizedBox(height: 34),
                    Text('House rules',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    _HouseRules(rules: property.houseRules!),
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
                  UnlockCard(
                    property: property,
                    contact: _contact,
                    onUnlocked: _refreshContact,
                    onRequireSignIn: _requireSignIn,
                  ),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openInquiry(property),
                      icon: const Icon(Icons.mail_outline_rounded, size: 20),
                      label: const Text('Send a free message'),
                    ),
                  ),

                  const SizedBox(height: 20),
                  _TenancyCard(
                    tenancy: _myTenancy,
                    onBook: () => _book(property),
                    onCheckIn: () => _setTenancy(
                      'checked_in',
                      'Checked in. The landlord has been told.',
                    ),
                    onMoveOut: () => _setTenancy(
                      'moved_out',
                      'Moved out. The landlord has been told.',
                    ),
                  ),

                  const SizedBox(height: 22),
                  const _SafetyNote(),

                  const SizedBox(height: 30),
                  PartnerRails(partners: _partners),

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

/// The landlord's rules for the house, if they set any.
class _HouseRules extends StatelessWidget {
  const _HouseRules({required this.rules});

  final String rules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Landlords write these as sentences or as a list; either renders sensibly.
    final lines = rules
        .split(RegExp(r'[\n•]|(?<=\.)\s+(?=[A-Z])'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: KhejaColors.amber.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: KhejaColors.amber.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle, size: 6, color: KhejaColors.amber),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      line,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: KhejaColors.zinc600,
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

/// Booking, checking in and moving out — the tenant's side of occupancy.
/// Each step notifies the landlord.
class _TenancyCard extends StatelessWidget {
  const _TenancyCard({
    required this.tenancy,
    required this.onBook,
    required this.onCheckIn,
    required this.onMoveOut,
  });

  final Tenancy? tenancy;
  final VoidCallback onBook;
  final VoidCallback onCheckIn;
  final VoidCallback onMoveOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = tenancy;

    if (t == null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onBook,
          icon: const Icon(Icons.event_available_rounded, size: 20),
          label: const Text('Book this home'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KhejaColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: KhejaColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: KhejaColors.emerald),
              const SizedBox(width: 10),
              Text(t.statusLabel, style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.status == 'booked'
                ? 'The landlord knows you intend to move in. Tell us when you '
                    'actually do, so they can update the listing.'
                : 'You are recorded as living here. Let us know when you move '
                    'out and the home goes back on the market.',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: KhejaColors.zinc500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          if (t.status == 'booked')
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCheckIn,
                icon: const Icon(Icons.login_rounded, size: 19),
                label: const Text('I have moved in'),
                style: FilledButton.styleFrom(backgroundColor: KhejaColors.emerald),
              ),
            )
          else if (t.status == 'checked_in')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onMoveOut,
                icon: const Icon(Icons.logout_rounded, size: 19),
                label: const Text('I have moved out'),
              ),
            ),
        ],
      ),
    );
  }
}
