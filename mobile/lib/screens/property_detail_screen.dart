import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/property_card.dart';
import '../widgets/partner_rails.dart';
import '../widgets/states.dart';
import '../widgets/unlock_card.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/video_player_view.dart';
import 'auth_screen.dart';
import 'availability_sheet.dart';
import 'inquiry_sheet.dart';
import 'request_sheet.dart';

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
  PropertyInterest? _myInterest;
  bool _watchBusy = false;
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
        khejaApi.fetchPartners().catchError((_) => <Partner>[]),
        khejaApi.fetchMyTenancyFor(property.id).catchError((_) => null),
        khejaApi.fetchInterestFor(property.id),
      ]);

      if (!mounted) return;
      setState(() {
        _similar = rest[0] as List<Property>;
        _contact = rest[1] as PropertyContact;
        _partners = rest[2] as List<Partner>;
        _myTenancy = rest[3] as Tenancy?;
        _myInterest = rest[4] as PropertyInterest?;
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

  bool _isOwner(Property property) => khejaApi.currentUser?.id == property.ownerId;

  Future<void> _request(Property property) async {
    if (!khejaApi.isSignedIn && !await _requireSignIn()) return;
    if (!mounted) return;
    final sent = await showKhejaSheet<bool>(context, RequestSheet(property: property));
    if (sent != true || !mounted) return;
    final tenancy = await khejaApi.fetchMyTenancyFor(property.id).catchError((_) => null);
    if (!mounted) return;
    setState(() => _myTenancy = tenancy);
    showKhejaSnack(context, 'Request sent. The landlord has been notified.');
  }

  /// "Notify me when this home is available."
  Future<void> _toggleWatch(Property property) async {
    if (!khejaApi.isSignedIn && !await _requireSignIn()) return;
    setState(() => _watchBusy = true);
    try {
      final current = _myInterest;
      if (current != null) {
        await khejaApi.cancelInterest(current.id);
        if (!mounted) return;
        setState(() => _myInterest = null);
        showKhejaSnack(context, 'You will no longer be notified about this home.');
      } else {
        await khejaApi.watchProperty(property.id);
        final interest = await khejaApi.fetchInterestFor(property.id);
        if (!mounted) return;
        setState(() => _myInterest = interest);
        showKhejaSnack(context, 'Done. We will notify you when this home is available.');
      }
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    } finally {
      if (mounted) setState(() => _watchBusy = false);
    }
  }

  Future<void> _setAvailability(Property property) async {
    final saved = await showKhejaSheet<bool>(context, AvailabilitySheet(property: property));
    if (saved == true && mounted) {
      showKhejaSnack(context, 'Availability updated.');
      await _load();
    }
  }

  Future<void> _withdraw() async {
    await _setTenancy('cancelled', 'Request withdrawn. The landlord has been told.');
  }

  Future<void> _setTenancy(String status, String message) async {
    final tenancy = _myTenancy;
    if (tenancy == null) return;
    try {
      await khejaApi.setTenancyStatus(tenancy.id, status);
      final updated =
          await khejaApi.fetchMyTenancyFor(tenancy.propertyId).catchError((_) => null);
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
                          property.locationLabel,
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
                  if (!property.isAvailableNow && !_isOwner(property)) ...[
                    const SizedBox(height: 14),
                    _AvailabilityPanel(
                      property: property,
                      watching: _myInterest != null,
                      busy: _watchBusy,
                      onToggle: () => _toggleWatch(property),
                    ),
                  ],
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
                  _ListingDetails(property: property),

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
                    unlocked: _contact.unlocked,
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
                      icon: const Icon(Icons.support_agent_rounded, size: 20),
                      label: const Text('Message Kheja_Link'),
                    ),
                  ),

                  const SizedBox(height: 20),
                  if (_isOwner(property))
                    _OwnerCard(
                      property: property,
                      onSetAvailability: () => _setAvailability(property),
                    )
                  else
                    _TenancyCard(
                      tenancy: _myTenancy,
                      canRequest: property.isRequestable,
                      onRequest: () => _request(property),
                      onWithdraw: _withdraw,
                      onCheckIn: () => _setTenancy(
                        'checked_in',
                        'Welcome home! The landlord has been told.',
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
      showKhejaSnack(
        context,
        khejaApi.isSignedIn
            ? 'Message sent. Our reply will appear in your Inbox.'
            : 'Message sent. Kheja_Link will call you back.',
      );
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
    // Photos first, then video tours, all in one swipeable strip.
    final items = <GalleryItem>[
      for (final image in property.images) GalleryItem.photo(image.url),
      for (final video in property.videos)
        GalleryItem.video(video.url, thumbnailUrl: video.thumbnailUrl),
    ];
    final videoCount = property.videos.length;

    return SliverAppBar(
      expandedHeight: 340,
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
            if (items.isEmpty)
              const PropertyImageView(url: null)
            else
              PageView.builder(
                controller: pageController,
                onPageChanged: onPageChanged,
                itemCount: items.length,
                itemBuilder: (_, index) {
                  final item = items[index];
                  return item.isVideo
                      ? VideoPlayerView(url: item.url, thumbnailUrl: item.thumbnailUrl)
                      : PropertyImageView(url: item.url, width: 900);
                },
              ),
            // Top scrim only — a full-height one would darken the video.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black38, Colors.transparent],
                    stops: [0, 0.3],
                  ),
                ),
              ),
            ),
            // Tell people there is a video to find, before they have swiped.
            if (videoCount > 0)
              Positioned(
                left: 20,
                bottom: 16,
                child: IgnorePointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: KhejaColors.blue,
                      borderRadius: BorderRadius.circular(KhejaRadius.sm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_fill_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          videoCount == 1 ? 'VIDEO TOUR' : '$videoCount VIDEOS',
                          style: kEyebrowStyle.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (items.length > 1)
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
                    '${imageIndex + 1} / ${items.length}',
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
      // Both sides shrink to fit rather than overflow: a long rent
      // ("KSh 120,000") on a small phone would not fit at full size.
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.pricePeriod == 'year' ? 'ANNUAL RENT' : 'MONTHLY RENT',
                  style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(property.priceLabel, style: theme.textTheme.headlineMedium),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('DEPOSIT',
                    style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${property.depositMonths} '
                    '${property.depositMonths == 1 ? 'month' : 'months'}',
                    style: theme.textTheme.titleLarge,
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
  const _LocationCard({required this.property, required this.unlocked});

  final Property property;

  /// The exact address and map pin are shown in the contact card once paid.
  final bool unlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = property.location;
    final description = property.nearby?.trim();

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
              if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.5),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (unlocked ? KhejaColors.emerald : KhejaColors.blue).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(KhejaRadius.md),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      unlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                      size: 16,
                      color: unlocked ? KhejaColors.emerald : KhejaColors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        unlocked
                            ? 'The exact address and Google Maps pin are in the contact card below.'
                            : 'The exact address, building and Google Maps pin open with the '
                                'landlord\'s contact when you tap Unlock contact.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: KhejaColors.zinc500,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
/// The tenant's side of a house request: send one, see where it stands, and
/// take the next step. Only offered for a home that is free right now.
class _TenancyCard extends StatelessWidget {
  const _TenancyCard({
    required this.tenancy,
    required this.canRequest,
    required this.onRequest,
    required this.onWithdraw,
    required this.onCheckIn,
    required this.onMoveOut,
  });

  final Tenancy? tenancy;
  final bool canRequest;
  final VoidCallback onRequest;
  final VoidCallback onWithdraw;
  final VoidCallback onCheckIn;
  final VoidCallback onMoveOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = tenancy;

    if (t == null) {
      if (!canRequest) return const SizedBox.shrink();
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onRequest,
          style: FilledButton.styleFrom(
            backgroundColor: KhejaColors.emerald,
            minimumSize: const Size.fromHeight(56),
          ),
          icon: const Icon(Icons.how_to_reg_rounded, size: 20),
          label: const Text('Request this house'),
        ),
      );
    }

    final (color, icon, body) = switch (t.status) {
      'booked' => (
          KhejaColors.amber,
          Icons.hourglass_top_rounded,
          'Your request has been sent. We will tell you when the landlord responds.',
        ),
      'viewed' => (
          KhejaColors.blue,
          Icons.visibility_rounded,
          'The landlord has seen your request.',
        ),
      'accepted' => (
          KhejaColors.emerald,
          Icons.check_circle_rounded,
          'The landlord accepted. Arrange the viewing or the move with them, then tell '
              'us when you move in.',
        ),
      _ => (
          KhejaColors.emerald,
          Icons.home_rounded,
          'You are recorded as living here. Let us know when you move out.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Your request: ${t.statusLabel}', style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: KhejaColors.zinc500,
              height: 1.5,
            ),
          ),
          if (t.landlordResponse != null && t.landlordResponse!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Landlord: "${t.landlordResponse!.trim()}"',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          if (t.status == 'accepted')
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
          if (t.canWithdraw)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onWithdraw,
                style: TextButton.styleFrom(foregroundColor: KhejaColors.red),
                child: const Text('Withdraw request'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown instead of "Request" when the home is not free now: occupied, coming
/// available, or temporarily off the market.
class _AvailabilityPanel extends StatelessWidget {
  const _AvailabilityPanel({
    required this.property,
    required this.watching,
    required this.busy,
    required this.onToggle,
  });

  final Property property;
  final bool watching;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AvailabilityChip.colorFor(property.availability);
    final from = property.availableFrom;

    final (title, body) = switch (property.availability) {
      'notice_given' => (
          'Currently occupied',
          from == null
              ? 'This home is expected to become available soon.'
              : 'Expected to be available from ${formatShortDate(from)}.',
        ),
      'unavailable' => (
          'Temporarily unavailable',
          'The landlord has taken this home off the market for now.',
        ),
      _ => (
          'Currently occupied',
          'Someone lives here at the moment. It cannot be requested yet.',
        ),
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_busy_rounded, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KhejaColors.zinc500, height: 1.45),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: watching
                ? OutlinedButton.icon(
                    onPressed: busy ? null : onToggle,
                    icon: const Icon(Icons.notifications_active_rounded, size: 19),
                    label: const Text("You'll be notified · Stop"),
                  )
                : FilledButton.icon(
                    onPressed: busy ? null : onToggle,
                    style: FilledButton.styleFrom(backgroundColor: color),
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.notifications_rounded, size: 19),
                    label: const Text('Notify me when available'),
                  ),
          ),
        ],
      ),
    );
  }
}

/// The landlord looking at their own listing.
class _OwnerCard extends StatelessWidget {
  const _OwnerCard({required this.property, required this.onSetAvailability});

  final Property property;
  final VoidCallback onSetAvailability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: KhejaColors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: KhejaColors.blue.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This is your listing', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            property.availabilityLabel ?? 'Shown to tenants as available now.',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KhejaColors.zinc500),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSetAvailability,
              icon: const Icon(Icons.event_available_rounded, size: 19),
              label: const Text('Set availability'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything a tenant asks before travelling to a viewing: utilities, costs
/// beyond rent, terms, parking, what is nearby. Only rows the landlord filled
/// in are shown, so a sparse listing does not look like a list of blanks.
class _ListingDetails extends StatelessWidget {
  const _ListingDetails({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = property;

    final rows = <({IconData icon, String label, String value})>[
      if (p.floorNumber != null)
        (icon: Icons.stairs_rounded, label: 'Floor', value: '${p.floorNumber}'),
      if (p.waterLabel != null)
        (
          icon: Icons.water_drop_rounded,
          label: 'Water',
          value: [p.waterLabel!, if (p.waterNotes?.trim().isNotEmpty ?? false) p.waterNotes!]
              .join(' — ')
        ),
      if (p.electricityLabel != null)
        (icon: Icons.bolt_rounded, label: 'Electricity', value: p.electricityLabel!),
      if (p.serviceCharge != null && p.serviceCharge! > 0)
        (
          icon: Icons.receipt_long_rounded,
          label: 'Service charge',
          value: '${formatPrice(p.serviceCharge!)} a month'
        ),
      if (p.minLeaseMonths != null && p.minLeaseMonths! > 0)
        (
          icon: Icons.event_note_rounded,
          label: 'Minimum lease',
          value: '${p.minLeaseMonths} ${p.minLeaseMonths == 1 ? 'month' : 'months'}'
        ),
      if (p.noticeMonths != null && p.noticeMonths! > 0)
        (
          icon: Icons.notifications_paused_rounded,
          label: 'Notice to leave',
          value: '${p.noticeMonths} ${p.noticeMonths == 1 ? 'month' : 'months'}'
        ),
      (
        icon: Icons.local_parking_rounded,
        label: 'Parking',
        value: p.parkingSpaces == 0
            ? 'None'
            : '${p.parkingSpaces} ${p.parkingSpaces == 1 ? 'space' : 'spaces'}'
      ),
      if (p.securityDetails?.trim().isNotEmpty ?? false)
        (icon: Icons.shield_rounded, label: 'Security', value: p.securityDetails!),
    ];

    final features = <String>[
      if (p.isFurnished) 'Furnished',
      if (p.isGated) 'Gated compound',
      if (p.hasBalcony) 'Balcony',
      if (p.internetReady) 'Internet ready',
      p.petsAllowed ? 'Pets allowed' : 'No pets',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Details', style: theme.textTheme.titleLarge),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(rows[i].icon, size: 19, color: KhejaColors.blue),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 108,
                        child: Text(
                          rows[i].label,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: KhejaColors.zinc500,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rows[i].value,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (i < rows.length - 1)
                  Divider(height: 1, color: theme.colorScheme.outline),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in features)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: (f == 'No pets' ? KhejaColors.zinc400 : KhejaColors.emerald)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(KhejaRadius.sm),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: f == 'No pets' ? KhejaColors.zinc500 : KhejaColors.emerald,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
