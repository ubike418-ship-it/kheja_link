import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/brand.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'property_detail_screen.dart';
import 'search_screen.dart';

/// The discovery screen: the hero, the category rail carried over from the
/// web app's circular menu, and the newest listings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The same six categories as the web circular menu. `hunt` means everything
/// and `premium` is a tier flag, not a property type — the rest map onto
/// property_types.slug.
const _categories = <({String id, String label, IconData icon, Color color})>[
  (id: 'hunt', label: 'All Homes', icon: Icons.home_rounded, color: KhejaColors.blue),
  (
    id: 'apartments',
    label: 'Apartments',
    icon: Icons.apartment_rounded,
    color: KhejaColors.purple
  ),
  (
    id: 'bedsitters',
    label: 'Bedsitters',
    icon: Icons.grid_view_rounded,
    color: Color(0xFFDB2777)
  ),
  (
    id: 'rooms',
    label: 'Single Rooms',
    icon: Icons.person_rounded,
    color: Color(0xFFEA580C)
  ),
  (
    id: 'shops',
    label: 'Shops',
    icon: Icons.storefront_rounded,
    color: Color(0xFF0891B2)
  ),
  (
    id: 'premium',
    label: 'Premium',
    icon: Icons.auto_awesome_rounded,
    color: KhejaColors.amber
  ),
];

const _categoryTypeSlug = <String, String>{
  'apartments': 'apartment',
  'bedsitters': 'bedsitter',
  'rooms': 'single_room',
  'shops': 'shop',
};

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Property>> _future;
  String _category = 'hunt';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Property>> _load() =>
      khejaApi.fetchProperties(perPage: 24, page: 1);

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  List<Property> _visible(List<Property> all) {
    if (_category == 'hunt') return all;
    if (_category == 'premium') return all.where((p) => p.isPremium).toList();
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

  PropertyFilters _filtersForCategory(String id) => switch (id) {
        'premium' => const PropertyFilters(premium: true),
        'hunt' => const PropertyFilters(),
        _ => PropertyFilters(typeSlug: _categoryTypeSlug[id]),
      };

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
            SliverToBoxAdapter(child: _Hero(onSearch: _openSearch)),
            SliverToBoxAdapter(
              child: _CategoryRail(
                selected: _category,
                onSelect: (id) => setState(() => _category = id),
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

class _Listings extends StatelessWidget {
  const _Listings({
    required this.future,
    required this.visible,
    required this.onRetry,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onBrowseAll,
  });

  final Future<List<Property>> future;
  final List<Property> Function(List<Property>) visible;
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
              return PropertyCard(
                property: property,
                onTap: () => onOpen(property),
                onToggleFavorite: () => onToggleFavorite(property),
              );
            },
          ),
        );
      },
    );
  }
}

/// The hero, echoing the web headline and its gradient-blob backdrop.
class _Hero extends StatelessWidget {
  const _Hero({required this.onSearch});

  final void Function({PropertyFilters? filters}) onSearch;

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 15, color: KhejaColors.blue),
                    SizedBox(width: 7),
                    Text(
                      "Meru's Next-Gen Rental Platform",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
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
      height: 108,
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
                width: 74,
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
                      maxLines: 1,
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
