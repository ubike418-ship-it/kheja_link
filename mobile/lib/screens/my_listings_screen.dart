import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/property_card.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';
import 'availability_sheet.dart';
import 'listing_editor_screen.dart';
import 'property_detail_screen.dart';
import 'tenant_requests_screen.dart';

/// A landlord's own listings, in every status. RLS lets an owner see their
/// drafts here while the public search only ever returns published homes.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late Future<List<Property>> _future;
  Map<String, ({int saved, int waiting})> _interest = const {};
  Map<String, int> _openRequests = const {};

  @override
  void initState() {
    super.initState();
    _future = khejaApi.fetchMyProperties();
    _loadCounts();
  }

  /// Who is waiting on each home, and how many requests need a reply. Never
  /// blocks the list: the counts simply appear when they arrive.
  Future<void> _loadCounts() async {
    final interest = await khejaApi.fetchInterestCounts();
    final requests =
        await khejaApi.fetchRequestsForOwner().catchError((_) => <OwnerRequest>[]);
    if (!mounted) return;
    final open = <String, int>{};
    for (final r in requests.where((r) => r.isOpen)) {
      open[r.propertyId] = (open[r.propertyId] ?? 0) + 1;
    }
    setState(() {
      _interest = interest;
      _openRequests = open;
    });
  }

  Future<void> _refresh() async {
    final future = khejaApi.fetchMyProperties();
    setState(() => _future = future);
    _loadCounts();
    await future;
  }

  Future<void> _setAvailability(Property property) async {
    final saved = await showKhejaSheet<bool>(context, AvailabilitySheet(property: property));
    if (saved == true && mounted) {
      showKhejaSnack(context, 'Availability updated. Anyone waiting is notified when it is free.');
      await _refresh();
    }
  }

  Future<void> _showInterested(Property property) async {
    await showKhejaSheet<void>(context, _InterestedSheet(property: property));
  }

  Future<void> _openEditor([String? propertyId]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ListingEditorScreen(propertyId: propertyId),
      ),
    );
    if (saved == true && mounted) _refresh();
  }

  Future<void> _changeStatus(Property property, String status) async {
    try {
      await khejaApi.setPropertyStatus(property.id, status);
      if (!mounted) return;
      showKhejaSnack(context, 'Listing marked as $status.');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _delete(Property property) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
        ),
        title: const Text('Delete this listing?'),
        content: Text('"${property.title}" will be removed permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: KhejaColors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await khejaApi.deleteProperty(property.id);
      if (!mounted) return;
      showKhejaSnack(context, 'Listing deleted.');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Listings')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: KhejaColors.emerald,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_home_work_rounded),
        label: const Text('Add property',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: _refresh,
        child: FutureBuilder<List<Property>>(
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

            final items = snapshot.data ?? const [];

            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 50),
                  KhejaEmptyState(
                    icon: Icons.home_work_rounded,
                    title: "You haven't listed a property yet",
                    message: 'Tap "Add property" to list your first house — free for now. '
                        'You can edit it, set its availability or take it down from here.',
                  ),
                ],
              );
            }

            final published = items.where((p) => p.status == 'published').length;
            final views = items.fold<int>(0, (sum, p) => sum + p.viewCount);

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _Stats(
                    total: items.length,
                    published: published,
                    views: views,
                  );
                }
                final property = items[index - 1];
                return _ListingRow(
                  property: property,
                  interest: _interest[property.id],
                  openRequests: _openRequests[property.id] ?? 0,
                  onSetAvailability: () => _setAvailability(property),
                  onViewRequests: () => Navigator.of(context)
                      .push(MaterialPageRoute(
                        builder: (_) => TenantRequestsScreen(propertyId: property.id),
                      ))
                      .then((_) => _refresh()),
                  onInterested: () => _showInterested(property),
                  onOpen: property.status == 'published'
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PropertyDetailScreen(slug: property.slug),
                            ),
                          )
                      : null,
                  onStatusChanged: (status) => _changeStatus(property, status),
                  onEdit: () => _openEditor(property.id),
                  onDelete: () => _delete(property),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({
    required this.total,
    required this.published,
    required this.views,
  });

  final int total;
  final int published;
  final int views;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value, Color color, IconData icon) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(KhejaRadius.lg),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 10),
              Text(value,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
              Text(label.toUpperCase(),
                  style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          stat('Listings', '$total', KhejaColors.blue, Icons.home_work_rounded),
          const SizedBox(width: 12),
          stat('Live', '$published', KhejaColors.emerald,
              Icons.check_circle_rounded),
          const SizedBox(width: 12),
          stat('Views', '$views', KhejaColors.purple, Icons.visibility_rounded),
        ],
      ),
    );
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({
    required this.property,
    required this.onStatusChanged,
    required this.onEdit,
    required this.onDelete,
    required this.onSetAvailability,
    required this.onViewRequests,
    required this.onInterested,
    required this.openRequests,
    this.interest,
    this.onOpen,
  });

  final Property property;
  final ({int saved, int waiting})? interest;
  final int openRequests;
  final VoidCallback onSetAvailability;
  final VoidCallback onViewRequests;
  final VoidCallback onInterested;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(KhejaRadius.md),
                child: SizedBox(
                  width: 78,
                  height: 66,
                  child: PropertyImageView(url: property.coverUrl, width: 200),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${property.locationLabel} · ${property.rentLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: KhejaColors.zinc500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (property.availabilityLabel != null) ...[
                      AvailabilityChip(property: property),
                      const SizedBox(height: 6),
                    ],
                    Row(
                      children: [
                        StatusPill(property.status),
                        const SizedBox(width: 10),
                        const Icon(Icons.visibility_rounded,
                            size: 13, color: KhejaColors.zinc400),
                        const SizedBox(width: 4),
                        Text(
                          '${property.viewCount}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: KhejaColors.zinc400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onSetAvailability,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.event_available_rounded, size: 18),
                label: const Text('Set availability'),
              ),
              OutlinedButton.icon(
                onPressed: onViewRequests,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: Badge(
                  isLabelVisible: openRequests > 0,
                  label: Text('$openRequests'),
                  child: const Icon(Icons.inbox_rounded, size: 18),
                ),
                label: const Text('View requests'),
              ),
              OutlinedButton.icon(
                onPressed: onInterested,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                icon: const Icon(Icons.favorite_border_rounded, size: 18),
                label: Text(
                  interest == null
                      ? 'Interested'
                      : 'Interested · ${interest!.waiting + interest!.saved}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue:
                      property.status == 'pending' ? 'draft' : property.status,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: theme.colorScheme.onSurface,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'published', child: Text('Published')),
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'rented', child: Text('Rented')),
                    DropdownMenuItem(value: 'archived', child: Text('Archived')),
                  ],
                  onChanged: (value) {
                    if (value != null && value != property.status) {
                      onStatusChanged(value);
                    }
                  },
                ),
              ),
              if (onOpen != null) ...[
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onOpen,
                  tooltip: 'View live listing',
                  icon: const Icon(Icons.open_in_new_rounded, size: 20),
                ),
              ],
              IconButton(
                onPressed: onEdit,
                tooltip: 'Edit listing',
                icon: const Icon(Icons.edit_rounded, size: 20),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete listing',
                icon: const Icon(Icons.delete_outline_rounded,
                    size: 20, color: KhejaColors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Who has saved this home, or asked to be told when it is free. First names
/// only — the database never sends a tenant's contact details here.
class _InterestedSheet extends StatelessWidget {
  const _InterestedSheet({required this.property});

  final Property property;

  @override
  Widget build(BuildContext context) {
    return KhejaSheet(
      title: 'Interested tenants',
      subtitle: property.title,
      actionLabel: 'Done',
      onAction: () => Navigator.of(context).pop(),
      children: [
        FutureBuilder<List<InterestedTenant>>(
          future: khejaApi.fetchInterestedTenants(property.id),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator(color: KhejaColors.blue)),
              );
            }
            if (snapshot.hasError) {
              return Text(describeError(snapshot.error!),
                  style: const TextStyle(color: KhejaColors.red, fontWeight: FontWeight.w700));
            }
            final people = snapshot.data ?? const [];
            if (people.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'Nobody yet. Tenants who save this home, or ask to be notified when it '
                  'is free, appear here.',
                  style: TextStyle(color: KhejaColors.zinc500, fontWeight: FontWeight.w600, height: 1.5),
                ),
              );
            }
            return Column(
              children: [
                for (final t in people)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: (t.kind == 'waiting' ? KhejaColors.purple : KhejaColors.red)
                          .withValues(alpha: 0.12),
                      child: Icon(
                        t.kind == 'waiting'
                            ? Icons.notifications_active_rounded
                            : Icons.favorite_rounded,
                        size: 18,
                        color: t.kind == 'waiting' ? KhejaColors.purple : KhejaColors.red,
                      ),
                    ),
                    title: Text(t.firstName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(
                      '${t.kind == 'waiting' ? 'Waiting for it to be free' : 'Saved it'} · '
                      '${formatRelativeDate(t.since).toLowerCase()}',
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'When you set this home to "Available now", everyone here is notified.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KhejaColors.zinc400),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
