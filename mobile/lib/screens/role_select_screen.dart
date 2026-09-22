import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../widgets/brand.dart';
import 'airbnb_soon_screen.dart';
import 'app_shell.dart';

/// The front door: three clear ways in.
///
///   Tenant    find a home
///   Landlord  list and manage property
///   Stays     short-term stays — coming soon, and only a coming-soon page
///
/// Choosing tenant or landlord goes straight into that app, where a short
/// guided tour runs the first time. Signing in happens when it is needed (to
/// save, request or list), not as a wall at the door. Once someone signs in,
/// the role on their account decides which app they see.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  Future<void> _choose(BuildContext context, String role) async {
    await AppState.instance.setChosenRole(role);
    if (!context.mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            const Center(child: LogoLockup(width: 190)),
            const SizedBox(height: 30),
            Text('Welcome to Kheja_Link', style: theme.textTheme.displaySmall),
            const SizedBox(height: 10),
            Text(
              'What brings you here? We will show you around.',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: KhejaColors.zinc500, height: 1.5),
            ),
            const SizedBox(height: 26),

            _RoleCard(
              icon: Icons.search_rounded,
              accent: KhejaColors.blue,
              eyebrow: 'TENANT',
              title: 'Find a Home',
              subtitle: 'Search and discover houses',
              points: const [
                'Search by type, area, rent and availability',
                'Save homes and get told when one frees up',
                "Request a house and track the landlord's reply",
              ],
              onTap: () => _choose(context, 'seeker'),
            ),
            const SizedBox(height: 14),
            _RoleCard(
              icon: Icons.vpn_key_rounded,
              accent: KhejaColors.emerald,
              eyebrow: 'LANDLORD',
              title: 'List Your Property',
              subtitle: 'List and manage properties',
              points: const [
                'List houses with photos and video tours — free for now',
                'Set availability and expected vacancy dates',
                'Receive tenant requests and respond',
              ],
              onTap: () => _choose(context, 'landlord'),
            ),
            const SizedBox(height: 14),
            _RoleCard(
              icon: Icons.nightlight_round,
              accent: KhejaColors.purple,
              eyebrow: 'STAYS',
              title: 'Stays',
              subtitle: 'Short-term, Airbnb-style stays',
              badge: 'COMING SOON',
              points: const [
                'Not open yet — join the list to hear first',
              ],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AirbnbSoonScreen(isRoot: false)),
              ),
            ),

            const SizedBox(height: 26),
            Center(
              child: Text(
                'You can switch later by signing out.',
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
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.accent,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color accent;
  final String eyebrow;
  final String? badge;
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
                        Row(
                          children: [
                            Text(eyebrow, style: kEyebrowStyle.copyWith(color: accent)),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: KhejaColors.amber,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(badge!,
                                    style: kEyebrowStyle.copyWith(color: Colors.white, fontSize: 8)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
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
