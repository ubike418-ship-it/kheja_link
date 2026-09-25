import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../services/onboarding.dart';
import '../services/role_switch.dart';
import '../widgets/brand.dart';
import '../widgets/coach_marks.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'airbnb_soon_screen.dart';
import 'alert_sheet.dart';
import '../widgets/partner_rails.dart';
import 'hunting_screen.dart';
import 'my_requests_screen.dart';
import 'notification_preferences_screen.dart';
import 'property_detail_screen.dart';
import 'search_screen.dart';

/// The tenant's home: the three ways into Kheja_Link, the category rail
/// carried over from the web's circular menu, and
/// the newest listings. The first time a tenant opens it, a short guided tour
/// runs over these same widgets.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The categories. `hunt` means everything, `premium` is a tier flag, the
/// bedroom counts are exact, and the rest map onto property_types.slug.
const _categories = <({String id, String label, IconData icon, Color color})>[
  (id: 'hunt', label: 'All Homes', icon: Icons.home_rounded, color: KhejaColors.blue),
  (id: 'bedsitters', label: 'Bedsitters', icon: Icons.grid_view_rounded, color: Color(0xFFDB2777)),
  (id: 'bed1', label: '1 Bedroom', icon: Icons.bed_rounded, color: Color(0xFF7C3AED)),
  (id: 'bed2', label: '2 Bedroom', icon: Icons.king_bed_rounded, color: Color(0xFF4F46E5)),
  (id: 'bed3', label: '3 Bedroom', icon: Icons.family_restroom_rounded, color: Color(0xFF0369A1)),
  (id: 'apartments', label: 'Apartments', icon: Icons.apartment_rounded, color: KhejaColors.purple),
  (id: 'bungalows', label: 'Premium Bungalows', icon: Icons.villa_rounded, color: Color(0xFF15803D)),
  (id: 'hostels', label: 'Hostels', icon: Icons.school_rounded, color: Color(0xFF0D9488)),
  (id: 'rooms', label: 'Single Rooms', icon: Icons.person_rounded, color: Color(0xFFEA580C)),
  (id: 'shops', label: 'Shops', icon: Icons.storefront_rounded, color: Color(0xFF0891B2)),
  (id: 'premium', label: 'Premium', icon: Icons.auto_awesome_rounded, color: KhejaColors.amber),
];

const _categoryTypeSlug = <String, String>{
  'apartments': 'apartment',
  'bedsitters': 'bedsitter',
  'rooms': 'single_room',
  'hostels': 'hostel',
  'shops': 'shop',
  'bungalows': 'bungalow',
};

const _categoryBedrooms = <String, int>{'bed1': 1, 'bed2': 2, 'bed3': 3};

/// Types that are never "an N-bedroom", so they stay out of those categories.
const _notBedroomTypes = {'single_room', 'hostel', 'shop', 'bedsitter', 'studio'};

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Property>> _future;
  String _category = 'hunt';

  BusinessSettings _settings = const BusinessSettings();
  HuntingService _hunting = HuntingService.none;

  /// The unlock price is never shown up front — only on the payment screen
  /// when a tenant taps "Unlock contact". Money talk on the home screen (the
  /// refund offer) is for people who have already paid for an unlock.
  bool _hasPaidUnlock = false;

  // What the guided tour points at.
  final _categoryKey = GlobalKey();
  final _searchKey = GlobalKey();
  final _listKey = GlobalKey();
  final _firstCardKey = GlobalKey();
  final _moveMateKey = GlobalKey();

  /// MoveMate Kenya, our moving partner — on the home screen and in the tour.
  Partner? _moveMate;

  bool _touring = false;
  int _seenTutorialRequest = AppState.instance.tutorialRequest;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadHunting();
    AppState.instance.addListener(_onAppState);
    // First run: wait for the listings so the tour can point at a real one.
    _future.whenComplete(() {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
    });
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onAppState);
    super.dispose();
  }

  void _onAppState() {
    final request = AppState.instance.tutorialRequest;
    if (request != _seenTutorialRequest) {
      _seenTutorialRequest = request;
      if (AppState.instance.tutorialRequestRole == 'tenant') _runTour();
    }
  }

  Future<List<Property>> _load() => khejaApi.fetchProperties(perPage: 24, page: 1);

  Future<void> _loadHunting() async {
    final cached = await khejaApi.cachedBusinessSettings();
    if (mounted) setState(() => _settings = cached);
    final results = await Future.wait<Object>([
      khejaApi.fetchBusinessSettings(),
      khejaApi.fetchHuntingService().catchError((_) => HuntingService.none),
      khejaApi.fetchUnlockedPropertyIds(),
      khejaApi.fetchPartners().catchError((_) => <Partner>[]),
    ]);
    if (!mounted) return;
    setState(() {
      _settings = results[0] as BusinessSettings;
      _hunting = results[1] as HuntingService;
      _hasPaidUnlock = (results[2] as Set<String>).isNotEmpty;
      _moveMate = (results[3] as List<Partner>)
          .where((p) => p.slug == 'movemate-kenya')
          .firstOrNull;
    });
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    unawaited(_loadHunting());
    await future;
  }

  Future<void> _maybeTour() async {
    final profile = khejaApi.isSignedIn
        ? await khejaApi.fetchProfile().catchError((_) => null)
        : null;
    if (!mounted || !Onboarding.isDue('tenant', profile)) return;
    await _runTour();
  }

  Future<void> _runTour() async {
    if (_touring || !mounted) return;
    _touring = true;

    await showCoachMarks(
      context,
      eyebrow: 'WELCOME',
      steps: [
        CoachStep(
          target: _categoryKey,
          icon: Icons.category_rounded,
          title: 'Search by property type',
          body: 'Tap the kind of home you are looking for and the list below changes to match.',
          chips: const [
            'Bedsitter',
            '1 Bedroom',
            '2 Bedroom',
            '3 Bedroom',
            'Apartments',
            'Premium Bungalows',
            'Hostels',
          ],
        ),
        CoachStep(
          target: _searchKey,
          icon: Icons.travel_explore_rounded,
          title: 'Search for what you want',
          body: 'Search by area, type and rent, and filter by availability. Every listing '
              'shows its photos and video tours, so you can judge a home before you travel.',
        ),
        CoachStep(
          target: _listKey,
          icon: Icons.vpn_key_rounded,
          color: KhejaColors.emerald,
          title: 'List a house',
          body: 'Are you a landlord? List your property on Kheja_Link and connect with '
              'potential tenants. Listing is free for now.',
        ),
        CoachStep(
          target: _firstCardKey,
          icon: Icons.info_rounded,
          color: KhejaColors.purple,
          title: 'Open a home for more information',
          body: 'Tap any home for its photos, videos, description, location, rent, type, '
              'amenities and availability. Tap the heart to save it — if it is occupied, '
              'ask to be notified when it frees up.',
        ),
        CoachStep(
          target: _moveMateKey,
          icon: Icons.local_shipping_rounded,
          color: const Color(0xFF2F8F2F),
          title: 'Moving? Meet MoveMate Kenya',
          body: 'MoveMate Kenya is our moving partner. Once you have found your home, they '
              'pack, load and move you anywhere in Meru and beyond. Tap the card to call '
              'them — their price is agreed with them directly.',
        ),
      ],
    );

    await Onboarding.complete('tenant');
    _touring = false;
    // No pricing at the end of the tour: the unlock price is shown only when a
    // tenant taps "Unlock contact" on a home they want.
  }

  List<Property> _visible(List<Property> all) {
    if (_category == 'hunt') return all;
    if (_category == 'premium') return all.where((p) => p.isPremium).toList();
    final beds = _categoryBedrooms[_category];
    if (beds != null) {
      return all
          .where((p) => p.bedrooms == beds && !_notBedroomTypes.contains(p.propertyType?.slug))
          .toList();
    }
    final slug = _categoryTypeSlug[_category];
    if (slug == null) return const [];
    return all.where((p) => p.propertyType?.slug == slug).toList();
  }

  Future<void> _toggleFavorite(Property property) async {
    try {
      final saved = await khejaApi.toggleFavorite(property.id);
      if (!mounted) return;
      setState(() => property.isFavorited = saved);
      showKhejaSnack(
        context,
        saved ? 'Saved to your list.' : 'Removed from your saved homes.',
      );
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  void _openProperty(Property property) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(slug: property.slug),
      ),
    );
  }

  void _openSearch({PropertyFilters? filters}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SearchScreen(initialFilters: filters, isRoot: false),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => _loadHunting());
  }

  Future<void> _newAlert() async {
    if (!khejaApi.isSignedIn) {
      _push(const MyRequestsScreen(initialTab: 1));
      return;
    }
    final saved = await showKhejaSheet<bool>(context, const SearchAlertSheet());
    if (saved == true && mounted) {
      showKhejaSnack(context, 'Alert saved. We will tell you when a match is available.');
    }
  }

  PropertyFilters _filtersForCategory(String id) {
    final beds = _categoryBedrooms[id];
    if (beds != null) return PropertyFilters(bedrooms: beds, exactBedrooms: true);
    return switch (id) {
      'premium' => const PropertyFilters(premium: true),
      'hunt' => const PropertyFilters(),
      _ => PropertyFilters(typeSlug: _categoryTypeSlug[id]),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              titleSpacing: 20,
              // Light/dark flips with a double tap anywhere in the app (see
              // DoubleTapThemeToggle in main.dart) — no toggle icon needed.
              title: const BrandLockup(size: 34, fontSize: 20),
              actions: [
                IconButton(
                  onPressed: () => _openSearch(),
                  icon: const Icon(Icons.search_rounded),
                  tooltip: 'Search rentals',
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(child: _Hero(onSearch: _openSearch, searchKey: _searchKey)),
            SliverToBoxAdapter(
              child: _Pathways(
                listKey: _listKey,
                onFind: () => _openSearch(),
                onList: () => openListAHouse(context),
                onStays: () => _push(const AirbnbSoonScreen(isRoot: false)),
              ),
            ),
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _categoryKey,
                child: _CategoryRail(
                  selected: _category,
                  onSelect: (id) => setState(() => _category = id),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  children: [
                    if (_hunting.isActive || (_hasPaidUnlock && _settings.refundsEnabled)) ...[
                      _HuntingCard(
                        settings: _settings,
                        service: _hunting,
                        onTap: () => _push(const HuntingScreen()),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _QuickActions(
                      onRequests: () => _push(const MyRequestsScreen()),
                      onAlert: _newAlert,
                      onPreferences: () => khejaApi.isSignedIn
                          ? _push(const NotificationPreferencesScreen())
                          : _push(const MyRequestsScreen()),
                    ),
                    const SizedBox(height: 16),
                    KeyedSubtree(
                      key: _moveMateKey,
                      child: MoveMateSpotlight(partner: _moveMate),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Eyebrow('Curated for you',
                              icon: Icons.auto_awesome_rounded),
                          const SizedBox(height: 8),
                          Text(
                            _categories
                                .firstWhere((c) => c.id == _category)
                                .label,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          _openSearch(filters: _filtersForCategory(_category)),
                      child: const Text('View all'),
                    ),
                  ],
                ),
              ),
            ),
            _Listings(
              future: _future,
              visible: _visible,
              firstCardKey: _firstCardKey,
              onRetry: _refresh,
              onOpen: _openProperty,
              onToggleFavorite: _toggleFavorite,
              onBrowseAll: () => setState(() => _category = 'hunt'),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

/// The three ways into Kheja_Link, side by side and never confusable.
class _Pathways extends StatelessWidget {
  const _Pathways({
    required this.listKey,
    required this.onFind,
    required this.onList,
    required this.onStays,
  });

  final GlobalKey listKey;
  final VoidCallback onFind;
  final VoidCallback onList;
  final VoidCallback onStays;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _PathCard(
                icon: Icons.search_rounded,
                color: KhejaColors.blue,
                title: 'Find a Home',
                caption: 'Tenant',
                onTap: onFind,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KeyedSubtree(
                key: listKey,
                child: _PathCard(
                  icon: Icons.vpn_key_rounded,
                  color: KhejaColors.emerald,
                  title: 'List a House',
                  caption: 'Landlord',
                  onTap: onList,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PathCard(
                icon: Icons.nightlight_round,
                color: KhejaColors.purple,
                title: 'Stays',
                caption: 'Coming soon',
                onTap: onStays,
                muted: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.caption,
    required this.onTap,
    this.muted = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String caption;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.10), Colors.transparent],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: muted ? color.withValues(alpha: 0.15) : color,
                  borderRadius: BorderRadius.circular(KhejaRadius.sm),
                ),
                child: Icon(icon, size: 18, color: muted ? color : Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, height: 1.15),
              ),
              const SizedBox(height: 2),
              Text(
                caption.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kEyebrowStyle.copyWith(color: color, fontSize: 8.5, letterSpacing: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown only to tenants who have already paid for an unlock: the refund for
/// giving us a house — or, for someone holding a House Hunting pass bought
/// before it was retired, that every listing is already unlocked.
class _HuntingCard extends StatelessWidget {
  const _HuntingCard({required this.settings, required this.service, required this.onTap});

  final BusinessSettings settings;
  final HuntingService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = service.isActive;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: active
                  ? const [KhejaColors.emerald, Color(0xFF047857)]
                  : const [KhejaColors.blue, KhejaColors.blueDark],
            ),
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(KhejaRadius.md),
                ),
                child: Icon(
                  active ? Icons.verified_rounded : Icons.travel_explore_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'UNLOCKS & REFUNDS',
                      style: kEyebrowStyle.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? 'Your House Hunting pass is active'
                          : 'Give us a house, get ${settings.refundLabel} back',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      active
                          ? 'Every listing is unlocked for you.'
                          : 'Know a vacant house? Tell us and we refund part of your unlock.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onRequests,
    required this.onAlert,
    required this.onPreferences,
  });

  final VoidCallback onRequests;
  final VoidCallback onAlert;
  final VoidCallback onPreferences;

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 64),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        );

    return Row(
      children: [
        action(Icons.inbox_rounded, 'My Requests', onRequests),
        const SizedBox(width: 8),
        action(Icons.add_alert_rounded, 'Notify me', onAlert),
        const SizedBox(width: 8),
        action(Icons.tune_rounded, 'Preferences', onPreferences),
      ],
    );
  }
}

class _Listings extends StatelessWidget {
  const _Listings({
    required this.future,
    required this.visible,
    required this.firstCardKey,
    required this.onRetry,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onBrowseAll,
  });

  final Future<List<Property>> future;
  final List<Property> Function(List<Property>) visible;
  final GlobalKey firstCardKey;
  final VoidCallback onRetry;
  final void Function(Property) onOpen;
  final Future<void> Function(Property) onToggleFavorite;
  final VoidCallback onBrowseAll;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Property>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(height: 20),
              itemBuilder: (_, __) => const PropertyCardSkeleton(),
            ),
          );
        }

        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: KhejaErrorState(
              message: describeError(snapshot.error!),
              onRetry: onRetry,
            ),
          );
        }

        final items = visible(snapshot.data ?? const []);

        if (items.isEmpty) {
          final hasAny = (snapshot.data ?? const []).isNotEmpty;
          return SliverToBoxAdapter(
            child: KhejaEmptyState(
              icon: Icons.auto_awesome_rounded,
              title: hasAny ? 'Almost there!' : 'No homes listed yet',
              message: hasAny
                  ? "We're verifying new homes in this category. Check back shortly."
                  : 'Kheja_Link is ready and waiting for its first listings.',
              actionLabel: hasAny ? 'Browse all homes' : null,
              onAction: hasAny ? onBrowseAll : null,
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 20),
            itemBuilder: (_, index) {
              final property = items[index];
              final card = PropertyCard(
                property: property,
                onTap: () => onOpen(property),
                onToggleFavorite: () => onToggleFavorite(property),
              );
              return index == 0 ? KeyedSubtree(key: firstCardKey, child: card) : card;
            },
          ),
        );
      },
    );
  }
}

/// The hero, echoing the web headline and its gradient-blob backdrop.
class _Hero extends StatelessWidget {
  const _Hero({required this.onSearch, required this.searchKey});

  final void Function({PropertyFilters? filters}) onSearch;
  final GlobalKey searchKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: -60,
            child: _Blob(color: KhejaColors.blue.withValues(alpha: 0.22), size: 220),
          ),
          Positioned(
            top: 40,
            right: -70,
            child: _Blob(color: KhejaColors.emerald.withValues(alpha: 0.20), size: 200),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The tagline pill the web hero carries is dropped on mobile:
              // the app bar already says Kheja_Link, and the vertical space is
              // better spent on the headline and listings.
              const SizedBox(height: 4),
              Text('Find Your', style: theme.textTheme.displaySmall),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [KhejaColors.blue, KhejaColors.emerald, KhejaColors.purple],
                ).createShader(bounds),
                child: Text(
                  'Dream Space.',
                  style: theme.textTheme.displaySmall?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Long-term rentals, apartments, shops and bedsitters across Meru. '
                'Reliable, verified and modern.',
                style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500),
              ),
              const SizedBox(height: 22),

              // Tapping opens the real search screen rather than pretending to
              // be an input here.
              Material(
                key: searchKey,
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(KhejaRadius.xl),
                child: InkWell(
                  onTap: () => onSearch(),
                  borderRadius: BorderRadius.circular(KhejaRadius.xl),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(KhejaRadius.xl),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        const Icon(Icons.place_rounded,
                            size: 20, color: KhejaColors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Where in Meru? (e.g. Makutano)',
                            style: TextStyle(
                              color: KhejaColors.zinc400,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: KhejaColors.blue,
                            borderRadius: BorderRadius.circular(KhejaRadius.md),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            children: [
                              Icon(Icons.search_rounded, size: 18, color: Colors.white),
                              SizedBox(width: 7),
                              Text(
                                'Explore',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: color, blurRadius: 90, spreadRadius: 40)],
        ),
      ),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.selected, required this.onSelect});

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final item = _categories[index];
          final isSelected = item.id == selected;

          return Semantics(
            selected: isSelected,
            button: true,
            child: GestureDetector(
              onTap: () => onSelect(item.id),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 78,
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      width: isSelected ? 62 : 56,
                      height: isSelected ? 62 : 56,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? item.color
                            : Theme.of(context).colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : Theme.of(context).colorScheme.outline,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: item.color.withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        item.icon,
                        size: isSelected ? 27 : 24,
                        color: isSelected ? Colors.white : KhejaColors.zinc500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onSurface
                            : KhejaColors.zinc500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
