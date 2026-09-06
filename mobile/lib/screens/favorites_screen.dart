import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';
import 'auth_screen.dart';
import 'property_detail_screen.dart';

/// The viewer's saved homes. Row Level Security scopes these to the signed-in
/// user, so nobody can read anyone else's shortlist.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  late Future<List<Property>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Property>> _load() => khejaApi.fetchFavorites();

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _remove(Property property) async {
    try {
      await khejaApi.toggleFavorite(property.id);
      if (!mounted) return;
      showKhejaSnack(context, 'Removed from your saved homes.');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Saved homes only exist for a signed-in user, so ask first rather than
    // showing a permanently empty list.
    if (!khejaApi.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Saved Homes')),
        body: KhejaEmptyState(
          icon: Icons.favorite_border_rounded,
          title: 'Sign in to save homes',
          message: 'Tap the heart on any listing and it will wait for you here — '
              'handy when you are comparing a few places.',
          actionLabel: 'Sign in',
          onAction: () async {
            await Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AuthScreen()));
            if (mounted) setState(() => _future = _load());
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Homes')),
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: _refresh,
        child: FutureBuilder<List<Property>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: 2,
                separatorBuilder: (_, __) => const SizedBox(height: 20),
                itemBuilder: (_, __) => const PropertyCardSkeleton(),
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
                  SizedBox(height: 60),
                  KhejaEmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'No saved homes yet',
                    message: 'Tap the heart on any listing and it will wait for '
                        'you here.',
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 20),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    '${items.length} ${items.length == 1 ? 'home' : 'homes'} '
                    'on your list',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: KhejaColors.zinc500,
                    ),
                  );
                }

                final property = items[index - 1];
                return PropertyCard(
                  property: property,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PropertyDetailScreen(slug: property.slug),
                      ),
                    );
                    // Coming back, the saved state may have changed.
                    if (mounted) _refresh();
                  },
                  onToggleFavorite: () => _remove(property),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
