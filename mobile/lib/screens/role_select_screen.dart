import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../widgets/brand.dart';
import 'auth_screen.dart';

/// The front door: tenant or landlord.
///
/// These are two different people doing two different jobs, so they get two
/// different doors, two different sign-in screens and two different apps once
/// inside. Choosing here decides which sign-in screen appears and what a
/// signed-out visitor sees. Once someone signs in, the role stored on their
/// account decides — so a landlord who wanders through the tenant door still
/// lands in the landlord app.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  Future<void> _choose(BuildContext context, String role) async {
    await AppState.instance.setChosenRole(role);
    if (!context.mounted) return;

    // Straight to the sign-in screen for that role. Signing in is where the
    // two paths genuinely diverge, so we do not make people hunt for it.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AuthScreen(role: role, isEntryPoint: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: LogoLockup(width: 190)),
              const SizedBox(height: 34),
              Text('Who are you?', style: theme.textTheme.displaySmall),
              const SizedBox(height: 10),
              Text(
                'Kheja_Link works differently for people looking for a home and for '
                'people renting one out.',
                style: theme.textTheme.bodyLarge
                    ?.copyWith(color: KhejaColors.zinc500, height: 1.5),
              ),
              const SizedBox(height: 30),

              _RoleCard(
                icon: Icons.search_rounded,
                accent: KhejaColors.blue,
                title: "I'm a tenant",
                subtitle: 'Looking for a place to rent',
                points: const [
                  'Search and filter every home in Meru',
                  'Save homes and get told when one frees up',
                  'Unlock the landlord\'s number and the exact location',
                ],
                onTap: () => _choose(context, 'seeker'),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.vpn_key_rounded,
                accent: KhejaColors.emerald,
                title: "I'm a landlord",
                subtitle: 'I have property to rent out',
                points: const [
                  'List houses with photos and video tours',
                  'See who has booked, moved in and moved out',
                  'Read inquiries and reply straight away',
                ],
                onTap: () => _choose(context, 'landlord'),
              ),

              const Spacer(),
              Center(
                child: Text(
                  'You can switch by signing out.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: KhejaColors.zinc400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.onTap,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final List<String> points;
  final VoidCallback onTap;

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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
            border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.4),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accent.withValues(alpha: 0.08), Colors.transparent],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(KhejaRadius.md),
                    ),
                    child: Icon(icon, size: 24, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleLarge),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: KhejaColors.zinc500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: accent),
                ],
              ),
              const SizedBox(height: 14),
              for (final point in points)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_rounded, size: 15, color: accent),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          point,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
