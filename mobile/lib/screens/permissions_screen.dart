import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../widgets/brand.dart';
import 'app_shell.dart';

/// Shown once, on first launch, before the app proper.
///
/// It explains what each permission buys the user before the system dialog
/// appears, which is both more honest and markedly better for accept rates
/// than firing the OS prompt cold. Everything here is optional — declining
/// leaves the app fully usable.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _busy = false;

  Future<void> _continue({required bool ask}) async {
    setState(() => _busy = true);

    if (ask) {
      try {
        // Notifications: for "a home you liked is vacant again".
        await Permission.notification.request();
        // Location: only to sort by what is nearest on first open.
        await Permission.locationWhenInUse.request();
      } catch (_) {
        // A device that refuses to even show the dialog is not a reason to
        // block someone from using the app.
      }
    }

    await AppState.instance.markPermissionsAsked();
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LogoMark(size: 64),
              const SizedBox(height: 28),
              Text('Two quick things.', style: theme.textTheme.displaySmall),
              const SizedBox(height: 12),
              Text(
                'Both are optional, and you can change them later in your phone '
                'settings.',
                style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500),
              ),
              const SizedBox(height: 36),

              const _PermissionRow(
                icon: Icons.notifications_active_rounded,
                color: KhejaColors.blue,
                title: 'Notifications',
                body: 'So we can tell you the moment a home you liked becomes '
                    'vacant. Saved homes go fast, and a few hours matters.',
              ),
              const SizedBox(height: 22),
              const _PermissionRow(
                icon: Icons.place_rounded,
                color: KhejaColors.emerald,
                title: 'Location',
                body: 'So the first homes you see are the ones near you, rather '
                    'than a random corner of Meru.',
              ),

              const Spacer(),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(KhejaRadius.lg),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 18, color: KhejaColors.zinc400),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'We never share your location, and notifications stay '
                        'inside the app.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: KhejaColors.zinc500,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              FilledButton(
                onPressed: _busy ? null : () => _continue(ask: true),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Allow and continue'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : () => _continue(ask: false),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: KhejaColors.zinc500,
                ),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(KhejaRadius.md),
          ),
          child: Icon(icon, size: 22, color: color),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: KhejaColors.zinc500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
