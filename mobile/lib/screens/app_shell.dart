import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_state.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/onboarding.dart';
import 'favorites_screen.dart';
import 'home_screen.dart';
import 'landlord_home_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';
import 'tenant_requests_screen.dart';

/// The tab shell.
///
/// House hunters and landlords are different people doing different jobs, so
/// they get different tabs. A signed-out visitor gets the hunter set, because
/// browsing is open to everyone — signing in is only required to act.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  Profile? _profile;
  int _unread = 0;
  Timer? _pollTimer;
  StreamSubscription<AuthState>? _authSub;

  List<GlobalKey<NavigatorState>> _navigatorKeys = [];
  int _seenTutorialRequest = AppState.instance.tutorialRequest;

  /// Signed in: the account's role decides. Signed out: the door they chose.
  bool get _isLandlord => khejaApi.isSignedIn
      ? (_profile?.isLandlord ?? AppState.instance.choseLandlord)
      : AppState.instance.choseLandlord;

  @override
  void initState() {
    super.initState();
    _rebuildKeys();
    _loadProfile();

    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut) {
        for (final key in _navigatorKeys) {
          key.currentState?.popUntil((route) => route.isFirst);
        }
        _loadProfile();
      }
    });

    // In-app notifications only, so a gentle poll is enough — there is no push
    // service to wake us.
    _pollTimer = Timer.periodic(const Duration(seconds: 45), (_) => _loadUnread());

    AppState.instance.addListener(_onAppState);
  }

  /// "Show me around again": back to the first tab, where the tour runs.
  void _onAppState() {
    final request = AppState.instance.tutorialRequest;
    if (request == _seenTutorialRequest || !mounted) return;
    _seenTutorialRequest = request;
    for (final key in _navigatorKeys) {
      key.currentState?.popUntil((route) => route.isFirst);
    }
    setState(() => _index = 0);
  }

  void _rebuildKeys() {
    _navigatorKeys = List.generate(5, (_) => GlobalKey<NavigatorState>());
  }

  Future<void> _loadProfile() async {
    final profile = khejaApi.isSignedIn
        ? await khejaApi.fetchProfile().catchError((_) => null)
        : null;
    if (!mounted) return;

    // A tour finished on this phone before signing in counts for the account.
    if (profile != null) {
      for (final (role, onAccount) in [
        ('tenant', profile.tenantOnboardedAt),
        ('landlord', profile.landlordOnboardedAt),
      ]) {
        if (onAccount == null && AppState.instance.hasToured(role)) {
          Onboarding.complete(role);
        }
      }
    }
    setState(() {
      _profile = profile;
      if (_index >= _tabs.length) _index = 0;
    });
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final count = await khejaApi.fetchUnreadNotificationCount();
    if (!mounted || count == _unread) return;
    setState(() => _unread = count);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _authSub?.cancel();
    AppState.instance.removeListener(_onAppState);
    super.dispose();
  }

  /// The tab set depends on who is signed in.
  List<({Widget screen, IconData icon, IconData activeIcon, String label})>
      get _tabs {
    if (_isLandlord) {
      return [
        (
          screen: const LandlordHomeScreen(),
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label: 'Dashboard'
        ),
        (
          screen: const TenantRequestsScreen(isRoot: true),
          icon: Icons.inbox_outlined,
          activeIcon: Icons.inbox_rounded,
          label: 'Requests'
        ),
        (
          screen: const SearchScreen(),
          icon: Icons.search_outlined,
          activeIcon: Icons.search_rounded,
          label: 'Browse'
        ),
        (
          screen: const NotificationsScreen(),
          icon: Icons.notifications_none_rounded,
          activeIcon: Icons.notifications_rounded,
          label: 'Alerts'
        ),
        (
          screen: const ProfileScreen(),
          icon: Icons.person_outline_rounded,
          activeIcon: Icons.person_rounded,
          label: 'Account'
        ),
      ];
    }

    return [
      (
        screen: const HomeScreen(),
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'Home'
      ),
      (
        screen: const SearchScreen(),
        icon: Icons.search_outlined,
        activeIcon: Icons.search_rounded,
        label: 'Search'
      ),
      (
        screen: const FavoritesScreen(),
        icon: Icons.favorite_border_rounded,
        activeIcon: Icons.favorite_rounded,
        label: 'Saved'
      ),
      (
        screen: const NotificationsScreen(),
        icon: Icons.notifications_none_rounded,
        activeIcon: Icons.notifications_rounded,
        label: 'Alerts'
      ),
      (
        screen: khejaApi.isSignedIn ? const ProfileScreen() : const ProfileScreen(),
        icon: khejaApi.isSignedIn ? Icons.person_outline_rounded : Icons.login_rounded,
        activeIcon: Icons.person_rounded,
        label: khejaApi.isSignedIn ? 'Account' : 'Sign in'
      ),
    ];
  }

  Future<bool> _handleBack() async {
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return false;
    }
    if (_index != 0) {
      setState(() => _index = 0);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    // The alerts tab is where the badge belongs, wherever it sits.
    final alertsIndex = tabs.indexWhere((t) => t.label == 'Alerts');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _handleBack() && mounted) navigator.pop();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < tabs.length; i++)
              _TabNavigator(navigatorKey: _navigatorKeys[i], child: tabs[i].screen),
          ],
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _index.clamp(0, tabs.length - 1),
            onTap: (next) {
              if (next == _index) {
                _navigatorKeys[next].currentState?.popUntil((r) => r.isFirst);
              }
              setState(() => _index = next);
              if (next == alertsIndex) _loadUnread();
            },
            items: [
              for (var i = 0; i < tabs.length; i++)
                BottomNavigationBarItem(
                  icon: _maybeBadge(Icon(tabs[i].icon), i == alertsIndex),
                  activeIcon: _maybeBadge(Icon(tabs[i].activeIcon), i == alertsIndex),
                  label: tabs[i].label,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _maybeBadge(Widget icon, bool show) {
    if (!show || _unread == 0) return icon;
    return Badge(
      label: Text(_unread > 9 ? '9+' : '$_unread'),
      child: icon,
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
