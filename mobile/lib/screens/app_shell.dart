import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import 'favorites_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// The bottom-tab shell. Each tab keeps its own navigation stack so, for
/// example, backing out of a property opens the list you came from.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  StreamSubscription<AuthState>? _authSub;

  final _navigatorKeys = List.generate(4, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    // Signing in or out changes what every tab should show, so rebuild the
    // shell and drop any stale stacks.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut) {
        for (final key in _navigatorKeys) {
          key.currentState?.popUntil((route) => route.isFirst);
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return false;
    }
    // Any tab other than Home returns to Home before leaving the app.
    if (_index != 0) {
      setState(() => _index = 0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Resolve the navigator first: nothing may cross the await below.
        final navigator = Navigator.of(context);
        if (await _onWillPop() && mounted) {
          navigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            _TabNavigator(navigatorKey: _navigatorKeys[0], child: const HomeScreen()),
            _TabNavigator(navigatorKey: _navigatorKeys[1], child: const SearchScreen()),
            _TabNavigator(
                navigatorKey: _navigatorKeys[2], child: const FavoritesScreen()),
            _TabNavigator(navigatorKey: _navigatorKeys[3], child: const ProfileScreen()),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (next) {
              // Tapping the active tab pops it back to its root.
              if (next == _index) {
                _navigatorKeys[next].currentState?.popUntil((r) => r.isFirst);
              }
              setState(() => _index = next);
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.search_outlined),
                activeIcon: Icon(Icons.search_rounded),
                label: 'Search',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.favorite_border_rounded),
                activeIcon: Icon(Icons.favorite_rounded),
                label: 'Saved',
              ),
              BottomNavigationBarItem(
                icon: Icon(khejaApi.isSignedIn
                    ? Icons.person_outline_rounded
                    : Icons.login_rounded),
                activeIcon: const Icon(Icons.person_rounded),
                label: khejaApi.isSignedIn ? 'Account' : 'Sign in',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => child, settings: settings),
    );
  }
}
