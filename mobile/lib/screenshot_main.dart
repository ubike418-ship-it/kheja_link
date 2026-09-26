// Store screenshots only — not part of the app on Google Play.
//
//   flutter build web -t lib/screenshot_main.dart
//
// then open index.html?screen=home|search|listing|hunting|roles
// [&slug=...] [&scroll=pixels] [&dark=1] and capture it at phone or tablet
// size. It shows the real screens against the live data, with the first-run
// tour switched off so nothing covers them.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_state.dart';
import 'config/supabase_config.dart';
import 'config/theme.dart';
import 'main.dart';
import 'screens/app_shell.dart';
import 'screens/hunting_screen.dart';
import 'screens/payment_sheet.dart';
import 'screens/property_detail_screen.dart';
import 'screens/role_select_screen.dart';
import 'screens/search_screen.dart';
import 'services/kheja_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env', isOptional: true);
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  khejaApi = KhejaApi(Supabase.instance.client);
  await AppState.instance.load();
  await AppState.instance.setChosenRole('seeker');
  await AppState.instance.markToured('tenant');
  await AppState.instance.markToured('landlord');

  final q = Uri.base.queryParameters;
  final dark = q['dark'] == '1';
  if (dark != AppState.instance.isDark) await AppState.instance.toggleTheme();

  final Widget screen = switch (q['screen']) {
    'search' => const SearchScreen(),
    'listing' => PropertyDetailScreen(slug: q['slug'] ?? ''),
    'hunting' => const HuntingScreen(),
    'roles' => const RoleSelectScreen(),
    // The M-Pesa screen as a tenant sees it after tapping "Unlock contact".
    // Nothing is charged: a payment only starts when "Pay" is tapped.
    'payment' => const Scaffold(
        backgroundColor: Color(0xFF3F3F46),
        body: Align(
          alignment: Alignment.bottomCenter,
          child: PaymentSheet(
            reference: 'kl_screenshot_only',
            amountLabel: 'KSh 500',
            title: 'Unlock contact',
            what: 'Landlord and caretaker numbers and the exact location for '
                '"Makutano ensuite", open for 3 hours.',
          ),
        ),
      ),
    _ => const AppShell(),
  };

  runApp(_Shot(
    dark: dark,
    scroll: double.tryParse(q['scroll'] ?? '') ?? 0,
    child: screen,
  ));
}

class _Shot extends StatefulWidget {
  const _Shot({required this.dark, required this.scroll, required this.child});

  final bool dark;
  final double scroll;
  final Widget child;

  @override
  State<_Shot> createState() => _ShotState();
}

class _ShotState extends State<_Shot> {
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.scroll > 0) {
      // Keep trying until the data has loaded far enough to scroll there.
      Timer.periodic(const Duration(milliseconds: 500), (t) {
        if (_scroll() || t.tick > 60) t.cancel();
      });
    }
  }

  bool _scroll() {
    ScrollableState? target;
    void visit(Element e) {
      if (target != null) return;
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        if (s.widget.axisDirection == AxisDirection.down && s.position.maxScrollExtent > 0) {
          target = s;
          return;
        }
      }
      e.visitChildren(visit);
    }

    _key.currentContext?.visitChildElements(visit);
    final position = target?.position;
    if (position == null || position.maxScrollExtent < widget.scroll) return false;
    position.jumpTo(widget.scroll);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      key: _key,
      debugShowCheckedModeBanner: false,
      theme: buildKhejaTheme(Brightness.light),
      darkTheme: buildKhejaTheme(Brightness.dark),
      themeMode: widget.dark ? ThemeMode.dark : ThemeMode.light,
      home: widget.child,
    );
  }
}
