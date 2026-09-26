import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../widgets/brand.dart';
import '../main.dart';
import 'app_shell.dart';
import 'role_select_screen.dart';

/// The first thing anyone sees: the Kheja_Link mark on the brand's own dark
/// ground, resolving into the wordmark, then the app.
///
/// This sits on top of the native splash, so there is no white flash between
/// the two — the colours are the same on both sides.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1650),
  );

  late final Animation<double> _markScale = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
  );

  late final Animation<double> _markFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
  );

  late final Animation<double> _wordFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.4, 0.75, curve: Curves.easeOut),
  );

  late final Animation<double> _tagFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.6, 0.9, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Let the animation breathe, but never hold the app hostage to it.
    final work = AppState.instance.load();
    await Future.wait([
      work,
      Future<void>.delayed(const Duration(milliseconds: 1750)),
    ]);

    if (!mounted) return;

    // A signed-in person goes straight in (their account decides which app),
    // and a signed-out one goes to the tenant/landlord door until they have
    // picked a side. No permissions are asked up front: location is asked only
    // when a landlord pins their house.
    final Widget next;
    if (khejaApi.isSignedIn || AppState.instance.hasChosenRole) {
      next = const AppShell();
    } else {
      next = const RoleSelectScreen();
    }

    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KhejaColors.brandInk,
      body: Stack(
        children: [
          // A soft brand glow behind the mark, so the dark ground is not flat.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 0.95,
                  colors: [
                    KhejaColors.blue.withValues(alpha: 0.28),
                    KhejaColors.brandInk,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: _markFade,
                      child: ScaleTransition(
                        scale: Tween(begin: 0.7, end: 1.0).animate(_markScale),
                        child: const LogoMark(size: 132, blurred: true),
                      ),
                    ),
                    const SizedBox(height: 30),
                    FadeTransition(
                      opacity: _wordFade,
                      child: const _Wordmark(),
                    ),
                    const SizedBox(height: 14),
                    FadeTransition(
                      opacity: _tagFade,
                      child: Text(
                        'FIND YOUR NEXT HOME IN MERU',
                        style: kEyebrowStyle.copyWith(
                          color: Colors.white.withValues(alpha: 0.55),
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 56,
            child: FadeTransition(
              opacity: _tagFade,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: const TextSpan(
        style: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: -1.4,
          color: Colors.white,
        ),
        children: [
          TextSpan(text: 'KHEJA'),
          TextSpan(text: '_LINK', style: TextStyle(color: KhejaColors.blue)),
        ],
      ),
    );
  }
}
