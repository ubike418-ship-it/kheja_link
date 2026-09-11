import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../widgets/brand.dart';
import '../widgets/states.dart';
import 'role_select_screen.dart';

/// Shown once, on first launch.
///
/// It explains each permission before Android asks, then really asks — and
/// reports what happened. In 1.1.x "Allow" did nothing because the permissions
/// were requested but never declared in the manifest, so Android refused them
/// silently and this screen moved on without noticing.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _busy = false;
  PermissionStatus? _notification;
  PermissionStatus? _location;

  Future<void> _requestAll() async {
    setState(() => _busy = true);

    // One at a time: Android shows one system dialog after another, and firing
    // them together can drop the second one on some devices.
    final notification = await _safeRequest(Permission.notification);
    if (!mounted) return;
    setState(() => _notification = notification);

    final location = await _safeRequest(Permission.locationWhenInUse);
    if (!mounted) return;
    setState(() {
      _location = location;
      _busy = false;
    });

    // If either was refused for good, the system dialog will never appear
    // again — the only way back is the app's settings page, so say so.
    final blocked = notification.isPermanentlyDenied || location.isPermanentlyDenied;
    if (blocked) {
      showKhejaSnack(
        context,
        'Some permissions are switched off for Kheja_Link. Turn them on in Settings.',
      );
      return;
    }

    await _finish();
  }

  Future<PermissionStatus> _safeRequest(Permission permission) async {
    try {
      final current = await permission.status;
      if (current.isGranted || current.isLimited) return current;
      return await permission.request();
    } catch (_) {
      return PermissionStatus.denied;
    }
  }

  Future<void> _finish() async {
    await AppState.instance.markPermissionsAsked();
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const RoleSelectScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asked = _notification != null || _location != null;
    final anyBlocked = (_notification?.isPermanentlyDenied ?? false) ||
        (_location?.isPermanentlyDenied ?? false);

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
                'Both are optional. Tap Allow and your phone will ask you for each '
                'one in turn.',
                style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500),
              ),
              const SizedBox(height: 36),

              _PermissionRow(
                icon: Icons.notifications_active_rounded,
                color: KhejaColors.blue,
                title: 'Notifications',
                body: 'So we can tell you the moment a home you liked becomes '
                    'vacant. Saved homes go fast, and a few hours matters.',
                status: _notification,
              ),
              const SizedBox(height: 22),
              _PermissionRow(
                icon: Icons.place_rounded,
                color: KhejaColors.emerald,
                title: 'Location',
                body: 'So the first homes you see are the ones near you, rather '
                    'than a random corner of Meru.',
                status: _location,
              ),

              const Spacer(),

              if (anyBlocked) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: KhejaColors.amber.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(KhejaRadius.lg),
                    border: Border.all(color: KhejaColors.amber.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.settings_rounded,
                          size: 18, color: KhejaColors.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Android will not ask again once a permission is refused. '
                          'Open Settings to turn it on.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open Settings'),
                ),
                const SizedBox(height: 10),
              ],

              FilledButton(
                onPressed: _busy ? null : (asked ? _finish : _requestAll),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(asked ? 'Continue' : 'Allow'),
              ),
              const SizedBox(height: 10),
              if (!asked)
                TextButton(
                  onPressed: _busy ? null : _finish,
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
    required this.status,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final PermissionStatus? status;

  @override
  Widget build(BuildContext context) {
    // Show the real outcome next to each permission, so the user can see that
    // tapping Allow did something.
    final (label, labelColor) = switch (status) {
      null => (null, null),
      PermissionStatus.granted || PermissionStatus.limited =>
        ('ALLOWED', KhejaColors.emerald),
      PermissionStatus.permanentlyDenied => ('BLOCKED', KhejaColors.red),
      _ => ('NOT ALLOWED', KhejaColors.amber),
    };

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
              Row(
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  if (label != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: labelColor!.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(label,
                          style: kEyebrowStyle.copyWith(color: labelColor, fontSize: 9)),
                    ),
                  ],
                ],
              ),
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
