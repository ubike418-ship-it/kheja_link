import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../services/onboarding.dart';
import '../widgets/brand.dart';
import '../widgets/coach_marks.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'airbnb_soon_screen.dart';
import 'auth_screen.dart';
import 'free_listing_screen.dart';
import 'inquiries_screen.dart';
import 'listing_editor_screen.dart';
import 'my_listings_screen.dart';
import 'notifications_screen.dart';
import 'property_detail_screen.dart';
import 'tenant_requests_screen.dart';

/// What a landlord sees on opening the app.
///
/// Deliberately not the house-hunter home: a landlord's job is to know what is
/// happening to their listings — who has asked, who wants in, what is free and
/// when — not to browse. The first time, a short tour runs over this screen.
class LandlordHomeScreen extends StatefulWidget {
  const LandlordHomeScreen({super.key});

  @override
  State<LandlordHomeScreen> createState() => _LandlordHomeScreenState();
}

class _LandlordHomeScreenState extends State<LandlordHomeScreen> {
  late Future<_LandlordDashboard> _future;
  BusinessSettings _settings = const BusinessSettings();

  final _addKey = GlobalKey();
  final _propertiesKey = GlobalKey();
  final _requestsKey = GlobalKey();
  final _alertsKey = GlobalKey();

  bool _touring = false;
  int _seenTutorialRequest = AppState.instance.tutorialRequest;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _loadSettings();
    AppState.instance.addListener(_onAppState);
    _future.then((d) => d.profile, onError: (_) => null).then((profile) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour(profile));
      }
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
      if (AppState.instance.tutorialRequestRole == 'landlord') _runTour();
    }
  }

  Future<void> _loadSettings() async {
    final cached = await khejaApi.cachedBusinessSettings();
    if (mounted) setState(() => _settings = cached);
    final live = await khejaApi.fetchBusinessSettings();
    if (mounted) setState(() => _settings = live);
  }

  Future<_LandlordDashboard> _load() async {
    if (!khejaApi.isSignedIn) return const _LandlordDashboard.signedOut();

    final results = await Future.wait([
      khejaApi.fetchProfile(),
      khejaApi.fetchMyProperties(),
      khejaApi.fetchInquiriesForOwner().catchError((_) => <Inquiry>[]),
      khejaApi.fetchTenanciesForOwner().catchError((_) => <Tenancy>[]),
      khejaApi.fetchRequestsForOwner().catchError((_) => <OwnerRequest>[]),
      khejaApi.fetchInterestCounts(),
    ]);

    return _LandlordDashboard(
      profile: results[0] as Profile?,
      properties: results[1] as List<Property>,
      inquiries: results[2] as List<Inquiry>,
      tenancies: results[3] as List<Tenancy>,
      requests: results[4] as List<OwnerRequest>,
      interest: results[5] as Map<String, ({int saved, int waiting})>,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    unawaited(_loadSettings());
    try {
      await future;
    } catch (_) {}
  }

  Future<void> _maybeTour(Profile? profile) async {
    if (!mounted || !Onboarding.isDue('landlord', profile)) return;
    await _runTour();
  }

  Future<void> _runTour() async {
    if (_touring || !mounted) return;
    _touring = true;

    await showCoachMarks(
      context,
      eyebrow: 'LANDLORDS',
      steps: [
        CoachStep(
          target: _addKey,
          icon: Icons.add_home_work_rounded,
          color: KhejaColors.emerald,
          title: 'List a house',
          body: 'List your property on Kheja_Link and make it easier for tenants to '
              'discover it. ${_settings.listingIsFree ? 'Listing is free for now.' : ''}',
        ),
        CoachStep(
          target: _propertiesKey,
          icon: Icons.home_work_rounded,
          title: 'Manage your properties',
          body: 'Add photos, video tours and details — type, rent, location. Mark a home '
              'occupied and set the date it will be free, so tenants can ask to be told.',
          chips: const ['Photos & videos', 'Rent', 'Location', 'Availability', 'Vacancy date'],
        ),
        CoachStep(
          target: _requestsKey,
          icon: Icons.inbox_rounded,
          color: KhejaColors.purple,
          title: 'Tenant requests',
          body: 'See who has requested each home and who is waiting for one to free up. '
              'Accept or decline — the tenant is told either way.',
        ),
        CoachStep(
          target: _alertsKey,
          icon: Icons.notifications_active_rounded,
          color: KhejaColors.amber,
          title: 'Your Inbox',
          body: 'You are notified of new requests, interest in your homes, and listing '
              'updates — all in your Inbox. Choose which under Account.',
        ),
      ],
    );

    await Onboarding.complete('landlord');
    _touring = false;
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const FreeListingScreen()),
    );
  }

  Future<void> _signIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthScreen(role: 'landlord')),
    );
    if (mounted) _refresh();
  }

  /// Everything on this screen belongs to an account; signed out, every action
  /// asks for one first.
  void _guarded(VoidCallback action) => khejaApi.isSignedIn ? action() : _signIn();

  void _push(Widget screen) {
    _guarded(() {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen))
          .then((_) => _refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: _refresh,
        child: FutureBuilder<_LandlordDashboard>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: KhejaColors.blue),
              );
            }
            if (snapshot.hasError && !snapshot.hasData) {
              return KhejaErrorState(
                message: describeError(snapshot.error!),
                onRetry: _refresh,
              );
            }

            final data = snapshot.data ?? const _LandlordDashboard.signedOut();
            final signedIn = data.profile != null;
            final published = data.properties.where((p) => p.status == 'published').length;
            final occupied = data.properties
                .where((p) => p.status == 'rented' || p.availability == 'occupied')
                .length;
            final comingUp = data.properties.where((p) => p.isComingAvailable).length;
            final newInquiries = data.inquiries.where((i) => i.status == 'new').length;
            final openRequests = data.requests.where((r) => r.isOpen).length;
            final waiting = data.interest.values.fold<int>(0, (sum, c) => sum + c.waiting);
            final activeTenants = data.tenancies.where((t) => t.isActive).length;
            final totalLikes = data.properties.fold<int>(0, (sum, p) => sum + p.likeCount);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Light/dark flips with a double tap anywhere in the app.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const BrandLockup(size: 34, fontSize: 19),
                        const Spacer(),
                        IconButton(
                          key: _alertsKey,
                          onPressed: () => _push(const NotificationsScreen()),
                          icon: const Icon(Icons.notifications_none_rounded),
                          tooltip: 'Inbox',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: KhejaColors.blue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: KhejaColors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.vpn_key_rounded, size: 13, color: KhejaColors.blue),
                      const SizedBox(width: 7),
                      Text('LANDLORD ACCOUNT',
                          style: kEyebrowStyle.copyWith(color: KhejaColors.blue)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  data.profile?.fullName != null
                      ? 'Karibu, ${data.profile!.firstName}.'
                      : 'Karibu.',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  !signedIn
                      ? 'List your houses, set when they are free, and answer tenant requests — '
                          'all from here. Sign in to get started.'
                      : data.properties.isEmpty
                          ? 'You have no listings yet. Add your first property below — '
                              'it goes live for tenants the moment you publish.'
                          : 'Here is what is happening across your ${data.properties.length} '
                              '${data.properties.length == 1 ? "listing" : "listings"}.',
                  style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500),
                ),
                const SizedBox(height: 18),

                if (_settings.listingIsFree) ...[
                  _OfferBanner(settings: _settings),
                  const SizedBox(height: 14),
                ],

                SizedBox(
                  key: _addKey,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _guarded(_addProperty),
                    style: FilledButton.styleFrom(
                      backgroundColor: KhejaColors.emerald,
                      minimumSize: const Size.fromHeight(58),
                    ),
                    icon: const Icon(Icons.add_home_work_rounded, size: 22),
                    label: Text(signedIn ? 'Add a property' : 'Sign in to list a house'),
                  ),
                ),
                const SizedBox(height: 22),

                // The landlord's tools, always visible — so it is obvious what
                // the app does even before signing in.
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.45,
                  children: [
                    KeyedSubtree(
                      key: _propertiesKey,
                      child: _StatCard(
                        icon: Icons.home_work_rounded,
                        color: KhejaColors.emerald,
                        value: signedIn ? '$published' : '—',
                        label: 'My properties',
                        caption: signedIn ? 'live of ${data.properties.length}' : null,
                        onTap: () => _push(const MyListingsScreen()),
                      ),
                    ),
                    KeyedSubtree(
                      key: _requestsKey,
                      child: _StatCard(
                        icon: Icons.inbox_rounded,
                        color: KhejaColors.purple,
                        value: signedIn ? '$openRequests' : '—',
                        label: 'Tenant requests',
                        caption: signedIn ? 'awaiting reply' : null,
                        highlight: openRequests > 0,
                        onTap: () => _push(const TenantRequestsScreen()),
                      ),
                    ),
                    _StatCard(
                      icon: Icons.event_available_rounded,
                      color: KhejaColors.amber,
                      value: signedIn ? '$occupied' : '—',
                      label: 'Availability',
                      caption: signedIn ? 'occupied · $comingUp coming up' : null,
                      onTap: () => _push(const MyListingsScreen()),
                    ),
                    _StatCard(
                      icon: Icons.favorite_rounded,
                      color: KhejaColors.red,
                      value: signedIn ? '$waiting' : '—',
                      label: 'Interested tenants',
                      caption: signedIn ? 'waiting · $totalLikes saved' : null,
                      onTap: () => _push(const MyListingsScreen()),
                    ),
                    _StatCard(
                      icon: Icons.mark_email_unread_rounded,
                      color: KhejaColors.blue,
                      value: signedIn ? '$newInquiries' : '—',
                      label: 'New inquiries',
                      highlight: newInquiries > 0,
                      onTap: () => _push(const InquiriesScreen()),
                    ),
                    _StatCard(
                      icon: Icons.nightlight_round,
                      color: KhejaColors.purple,
                      value: 'Soon',
                      label: 'Stays',
                      caption: 'short-term hosting',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const AirbnbSoonScreen(isRoot: false))),
                    ),
                  ],
                ),

                if (!signedIn) ...[
                  const SizedBox(height: 24),
                  _EmptyPanel(
                    icon: Icons.lock_outline_rounded,
                    text: 'Sign in or create a landlord account to see your listings, '
                        'requests and interested tenants here.',
                  ),
                ] else ...[
                  const SizedBox(height: 30),

                  // Occupancy: who has requested, moved in, moved out.
                  Row(
                    children: [
                      Text('Tenants', style: theme.textTheme.titleLarge),
                      const SizedBox(width: 10),
                      if (activeTenants > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: KhejaColors.emerald,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('$activeTenants ACTIVE',
                              style: kEyebrowStyle.copyWith(color: Colors.white, fontSize: 9)),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _push(const TenantRequestsScreen()),
                        child: const Text('All requests'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (data.tenancies.isEmpty)
                    _EmptyPanel(
                      icon: Icons.people_outline_rounded,
                      text: 'No tenant requests yet. When someone requests a home, moves in '
                          'or moves out, it shows here and you get a notification.',
                    )
                  else
                    ...data.tenancies.take(5).map((t) => _TenancyRow(tenancy: t)),

                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Text('Your listings', style: theme.textTheme.titleLarge),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _push(const MyListingsScreen()),
                        child: const Text('Manage'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (data.properties.isEmpty)
                    _EmptyPanel(
                      icon: Icons.home_work_outlined,
                      text: "You haven't listed a property yet. Tap \"Add a property\" above — "
                          'photos, a video tour and the details tenants ask about.',
                    )
                  else
                    ...data.properties.take(3).map(
                          (p) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: PropertyCard(
                              property: p,
                              imageHeight: 180,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => PropertyDetailScreen(slug: p.slug),
                                ),
                              ),
                            ),
                          ),
                        ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _addProperty() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ListingEditorScreen()),
    );
    if (saved == true && mounted) _refresh();
  }
}

class _LandlordDashboard {
  const _LandlordDashboard({
    required this.profile,
    required this.properties,
    required this.inquiries,
    required this.tenancies,
    required this.requests,
    required this.interest,
  });

  const _LandlordDashboard.signedOut()
      : profile = null,
        properties = const [],
        inquiries = const [],
        tenancies = const [],
        requests = const [],
        interest = const {};

  final Profile? profile;
  final List<Property> properties;
  final List<Inquiry> inquiries;
  final List<Tenancy> tenancies;
  final List<OwnerRequest> requests;
  final Map<String, ({int saved, int waiting})> interest;
}

/// "Free Property Listing — Limited-Time Offer", from app_settings. An end
/// date is only shown when one has been set.
class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.settings});

  final BusinessSettings settings;

  @override
  Widget build(BuildContext context) {
    final ends = settings.listingOfferEndsOn;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KhejaColors.emerald.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        border: Border.all(color: KhejaColors.emerald.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_offer_rounded, color: KhejaColors.emerald, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ends == null
                  ? settings.listingOfferLabel
                  : '${settings.listingOfferLabel} · ends ${formatShortDate(ends)}',
              style: const TextStyle(fontWeight: FontWeight.w900, color: KhejaColors.emerald),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
    this.caption,
    this.highlight = false,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? caption;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
            border: Border.all(
              color: highlight ? color.withValues(alpha: 0.5) : theme.colorScheme.outline,
              width: highlight ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  const Spacer(),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kEyebrowStyle.copyWith(color: theme.colorScheme.onSurface)),
              if (caption != null)
                Text(
                  caption!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: KhejaColors.zinc400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TenancyRow extends StatelessWidget {
  const _TenancyRow({required this.tenancy});

  final Tenancy tenancy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, color) = switch (tenancy.status) {
      'booked' || 'viewed' => (Icons.inbox_rounded, KhejaColors.purple),
      'accepted' => (Icons.check_circle_rounded, KhejaColors.blue),
      'declined' => (Icons.cancel_rounded, KhejaColors.red),
      'checked_in' => (Icons.login_rounded, KhejaColors.emerald),
      'moved_out' => (Icons.logout_rounded, KhejaColors.amber),
      _ => (Icons.cancel_rounded, KhejaColors.zinc400),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(KhejaRadius.sm),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tenancy.propertyTitle ?? 'A listing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  '${tenancy.statusLabel} · '
                  '${formatRelativeDate(tenancy.movedOutAt ?? tenancy.checkedInAt ?? tenancy.bookedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: KhejaColors.zinc500,
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

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: KhejaColors.zinc300),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: KhejaColors.zinc500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
