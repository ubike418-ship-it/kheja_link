import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'property_detail_screen.dart';

/// A landlord's own listings, in every status. RLS lets an owner see their
/// drafts here while the public search only ever returns published homes.
class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  late Future<List<Property>> _future;

  @override
  void initState() {
    super.initState();
    _future = khejaApi.fetchMyProperties();
  }

  Future<void> _refresh() async {
    final future = khejaApi.fetchMyProperties();
    setState(() => _future = future);
    await future;
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
                    title: 'No listings yet',
                    message: 'Listings you publish from the Kheja_Link website will '
                        'appear here, where you can take them down, mark them '
                        'rented or delete them.',
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
                  onOpen: property.status == 'published'
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PropertyDetailScreen(slug: property.slug),
                            ),
                          )
                      : null,
                  onStatusChanged: (status) => _changeStatus(property, status),
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
    required this.onDelete,
    this.onOpen,
  });

  final Property property;
  final ValueChanged<String> onStatusChanged;
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
                  child: PropertyImageView(url: property.coverUrl),
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
