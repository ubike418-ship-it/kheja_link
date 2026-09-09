import 'dart:async';

import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'filter_sheet.dart';
import 'property_detail_screen.dart';

/// Search and filtering over live listings — the mobile counterpart of the
/// web app's /properties page, running the same query against Supabase.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialFilters, this.isRoot = true});

  final PropertyFilters? initialFilters;

  /// When false the screen was pushed onto a stack and gets a back button.
  final bool isRoot;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const _perPage = 12;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  late PropertyFilters _filters;

  final List<Property> _results = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _page = 1;
  Timer? _debounce;

  List<SearchSuggestion> _suggestions = const [];
  bool _showSuggestions = false;
  final _searchFocus = FocusNode();

  // Reference data for the filter sheet, loaded once.
  List<PropertyType> _types = const [];
  List<KhejaLocation> _locations = const [];
  List<Amenity> _amenities = const [];
  ({num min, num max})? _bounds;

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters ?? const PropertyFilters();
    _searchController.text = _filters.query ?? '';
    _scrollController.addListener(_onScroll);
    _loadReferenceData();
    _search(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    try {
      final results = await Future.wait([
        khejaApi.fetchPropertyTypes(),
        khejaApi.fetchLocations(),
        khejaApi.fetchAmenities(),
        khejaApi.fetchPriceBounds(),
      ]);
      if (!mounted) return;
      setState(() {
        _types = results[0] as List<PropertyType>;
        _locations = results[1] as List<KhejaLocation>;
        _amenities = results[2] as List<Amenity>;
        _bounds = results[3] as ({num min, num max});
      });
    } catch (_) {
      // The filter sheet degrades to whatever loaded; search still works.
    }
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  Future<void> _search({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _error = null;
        _page = 1;
        _hasMore = true;
        _results.clear();
      });
    }

    try {
      final items = await khejaApi.fetchProperties(
        filters: _filters,
        page: _page,
        perPage: _perPage,
      );
      if (!mounted) return;
      setState(() {
        _results.addAll(items);
        _hasMore = items.length == _perPage;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = describeError(error);
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _isLoadingMore = true;
      _page += 1;
    });
    await _search();
  }

  /// Debounced so nothing fires on every keystroke. Suggestions come back
  /// quickly; the full search waits until the typing settles.
  void _onQueryChanged(String value) {
    _debounce?.cancel();

    final trimmed = value.trim();
    if (trimmed.length < 2) {
      setState(() {
        _suggestions = const [];
        _showSuggestions = false;
      });
    }

    _debounce = Timer(const Duration(milliseconds: 280), () async {
      final hints = await khejaApi.fetchSearchSuggestions(trimmed);
      if (!mounted) return;
      setState(() {
        _suggestions = hints;
        _showSuggestions = hints.isNotEmpty && _searchFocus.hasFocus;
      });
    });
  }

  /// Runs the search for whatever is currently typed.
  void _submitTyped() {
    _debounce?.cancel();
    final trimmed = _searchController.text.trim();
    setState(() {
      _filters = _filters.copyWith(query: trimmed.isEmpty ? null : trimmed);
      _showSuggestions = false;
    });
    _searchFocus.unfocus();
    _search(reset: true);
  }

  /// Applies a suggestion. An area or a house type becomes a real filter rather
  /// than a text match, which gives a much better result than the words would.
  void _applySuggestion(SearchSuggestion suggestion) {
    _debounce?.cancel();
    _searchFocus.unfocus();
    setState(() {
      _showSuggestions = false;
      _suggestions = const [];
    });

    switch (suggestion.kind) {
      case SuggestionKind.location:
        _searchController.clear();
        setState(() => _filters =
            _filters.copyWith(query: null, locationSlug: suggestion.value));
        _search(reset: true);

      case SuggestionKind.type:
        _searchController.clear();
        setState(() =>
            _filters = _filters.copyWith(query: null, typeSlug: suggestion.value));
        _search(reset: true);

      case SuggestionKind.property:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PropertyDetailScreen(slug: suggestion.value),
          ),
        );
    }
  }

  Future<void> _openFilters() async {
    final updated = await showModalBottomSheet<PropertyFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterSheet(
        filters: _filters,
        types: _types,
        locations: _locations,
        amenities: _amenities,
        bounds: _bounds,
      ),
    );

    if (updated != null && mounted) {
      setState(() => _filters = updated);
      _search(reset: true);
    }
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() => _filters = const PropertyFilters());
    _search(reset: true);
  }

  Future<void> _toggleFavorite(Property property) async {
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

  @override
  Widget build(BuildContext context) {
    final activeCount = _filters.activeCount;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isRoot,
        title: const Text('Search Rentals'),
        actions: [
          if (activeCount > 0)
            TextButton(onPressed: _clearFilters, child: const Text('Clear')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _onQueryChanged,
                    onTap: () => setState(
                        () => _showSuggestions = _suggestions.isNotEmpty),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submitTyped(),
                    decoration: InputDecoration(
                      hintText: 'Homes, areas or house types…',
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: KhejaColors.blue, size: 22),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setState(() =>
                                    _filters = _filters.copyWith(query: null));
                                _search(reset: true);
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _FilterButton(count: activeCount, onPressed: _openFilters),
              ],
            ),
          ),
          if (_showSuggestions) _SuggestionList(
            suggestions: _suggestions,
            onPick: _applySuggestion,
          ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isLoading) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(height: 20),
        itemBuilder: (_, __) => const PropertyCardSkeleton(),
      );
    }

    if (_error != null) {
      return KhejaErrorState(message: _error!, onRetry: () => _search(reset: true));
    }

    if (_results.isEmpty) {
      return KhejaEmptyState(
        icon: Icons.explore_rounded,
        title: 'No homes match that search',
        message: 'Try widening your budget, choosing a nearby area, or clearing a '
            'filter or two. New homes are added every week.',
        actionLabel: _filters.activeCount > 0 || _filters.query != null
            ? 'Clear all filters'
            : null,
        onAction: _clearFilters,
      );
    }

    return RefreshIndicator(
      color: KhejaColors.blue,
      onRefresh: () => _search(reset: true),
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _results.length + 2,
        separatorBuilder: (_, __) => const SizedBox(height: 20),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_results.length}${_hasMore ? '+' : ''} '
                '${_results.length == 1 ? 'home' : 'homes'} available',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: KhejaColors.zinc500,
                ),
              ),
            );
          }

          if (index == _results.length + 1) {
            if (_isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: KhejaColors.blue),
                  ),
                ),
              );
            }
            return const SizedBox(height: 8);
          }

          final property = _results[index - 1];
          return PropertyCard(
            property: property,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PropertyDetailScreen(slug: property.slug),
              ),
            ),
            onToggleFavorite: () => _toggleFavorite(property),
          );
        },
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isActive = count > 0;
    final theme = Theme.of(context);

    return Material(
      color: isActive ? KhejaColors.blue : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.md),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(KhejaRadius.md),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.md),
            border: Border.all(
              color: isActive ? KhejaColors.blue : theme.colorScheme.outline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 20,
                color: isActive ? Colors.white : KhejaColors.zinc500,
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      color: KhejaColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Live suggestions under the search box.
///
/// Areas and house types apply as real filters rather than as a text match,
/// which returns far better results than the words alone would; a listing
/// title opens that listing directly.
class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onPick});

  final List<SearchSuggestion> suggestions;
  final void Function(SearchSuggestion) onPick;

  static IconData _icon(SuggestionKind kind) => switch (kind) {
        SuggestionKind.location => Icons.place_rounded,
        SuggestionKind.type => Icons.home_work_rounded,
        SuggestionKind.property => Icons.article_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      constraints: const BoxConstraints(maxHeight: 290),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        border: Border.all(color: theme.colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: theme.colorScheme.outline),
        itemBuilder: (context, i) {
          final s = suggestions[i];
          return ListTile(
            dense: true,
            onTap: () => onPick(s),
            leading: Icon(_icon(s.kind), size: 19, color: KhejaColors.blue),
            title: Text(
              s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            trailing: Text(
              s.hint.toUpperCase(),
              style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
            ),
          );
        },
      ),
    );
  }
}
