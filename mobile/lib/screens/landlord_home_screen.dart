import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'inquiries_screen.dart';
import 'my_listings_screen.dart';
import 'notifications_screen.dart';
import 'property_detail_screen.dart';

/// What a landlord sees on opening the app.
///
/// Deliberately not the house-hunter home: a landlord's job is to know what is
/// happening to their listings — who has asked, who has booked, who has moved
/// in or out — not to browse.
class LandlordHomeScreen extends StatefulWidget {
  const LandlordHomeScreen({super.key});

  @override
  State<LandlordHomeScreen> createState() => _LandlordHomeScreenState();
}

class _LandlordHomeScreenState extends State<LandlordHomeScreen> {
  late Future<_LandlordDashboard> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_LandlordDashboard> _load() async {
    final results = await Future.wait([
      khejaApi.fetchProfile(),
      khejaApi.fetchMyProperties(),
      khejaApi.fetchInquiriesForOwner().catchError((_) => <Inquiry>[]),
      khejaApi.fetchTenanciesForOwner().catchError((_) => <Tenancy>[]),
    ]);

    return _LandlordDashboard(
      profile: results[0] as Profile?,
      properties: results[1] as List<Property>,
      inquiries: results[2] as List<Inquiry>,
      tenancies: results[3] as List<Tenancy>,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
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
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: KhejaColors.blue),
              );
            }
            if (snapshot.hasError) {
              return KhejaErrorState(
                message: describeError(snapshot.error!),
                onRetry: _refresh,
              );
            }

            final data = snapshot.data!;
            final published =
                data.properties.where((p) => p.status == 'published').length;
            final occupied =
                data.properties.where((p) => p.status == 'rented').length;
            final newInquiries =
                data.inquiries.where((i) => i.status == 'new').length;
            final activeTenants =
                data.tenancies.where((t) => t.isActive).length;
            final totalLikes =
                data.properties.fold<int>(0, (sum, p) => sum + p.likeCount);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Double tap anywhere on the header to flip light/dark.
                GestureDetector(
                  onDoubleTap: AppState.instance.toggleTheme,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const BrandLockup(size: 34, fontSize: 19),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const NotificationsScreen()),
                          ),
                          icon: const Icon(Icons.notifications_none_rounded),
                          tooltip: 'Notifications',
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
                    border:
                        Border.all(color: KhejaColors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.vpn_key_rounded,
                          size: 13, color: KhejaColors.blue),
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
                  data.properties.isEmpty
                      ? 'You have no listings yet. Add your first house from the '
                          'website and manage everything here.'
                      : 'Here is what is happening across your ${data.properties.length} '
                          '${data.properties.length == 1 ? "listing" : "listings"}.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: KhejaColors.zinc500),
                ),
                const SizedBox(height: 26),

                // Counts, which is what a landlord actually opens the app for.
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  children: [
                    _StatCard(
                      icon: Icons.check_circle_rounded,
                      color: KhejaColors.emerald,
                      value: '$published',
                      label: 'Live listings',
                      onTap: () => _openListings(),
                    ),
                    _StatCard(
                      icon: Icons.meeting_room_rounded,
                      color: KhejaColors.amber,
                      value: '$occupied',
                      label: 'Occupied',
                      onTap: () => _openListings(),
                    ),
                    _StatCard(
                      icon: Icons.mark_email_unread_rounded,
                      color: KhejaColors.blue,
                      value: '$newInquiries',
                      label: 'New inquiries',
                      highlight: newInquiries > 0,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const InquiriesScreen()),
                      ),
                    ),
                    _StatCard(
                      icon: Icons.favorite_rounded,
                      color: KhejaColors.red,
                      value: '$totalLikes',
                      label: 'Total likes',
                      onTap: () => _openListings(),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // Occupancy: who has booked, moved in, moved out.
                Row(
                  children: [
                    Text('Tenants', style: theme.textTheme.titleLarge),
                    const SizedBox(width: 10),
                    if (activeTenants > 0)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: KhejaColors.emerald,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('$activeTenants ACTIVE',
                            style:
                                kEyebrowStyle.copyWith(color: Colors.white, fontSize: 9)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                if (data.tenancies.isEmpty)
                  _EmptyPanel(
                    icon: Icons.people_outline_rounded,
                    text: 'Nobody has booked yet. When someone books, checks in '
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
                      onPressed: _openListings,
                      child: const Text('Manage'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (data.properties.isEmpty)
                  _EmptyPanel(
                    icon: Icons.home_work_outlined,
                    text: 'Add your first house on the Kheja_Link website and it '
                        'will appear here straight away.',
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
                                builder: (_) =>
                                    PropertyDetailScreen(slug: p.slug),
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openListings() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const MyListingsScreen()))
        .then((_) => _refresh());
  }
}

class _LandlordDashboard {
  const _LandlordDashboard({
    required this.profile,
    required this.properties,
    required this.inquiries,
    required this.tenancies,
  });

  final Profile? profile;
  final List<Property> properties;
  final List<Inquiry> inquiries;
  final List<Tenancy> tenancies;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
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
          padding: const EdgeInsets.all(16),
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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(KhejaRadius.sm),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const Spacer(),
              Text(value,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              Text(label.toUpperCase(),
                  style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
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
      'booked' => (Icons.event_available_rounded, KhejaColors.purple),
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
