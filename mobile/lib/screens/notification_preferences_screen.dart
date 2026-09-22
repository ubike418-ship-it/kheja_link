import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/states.dart';

/// Which alerts a person gets, and how.
///
/// The database reads these before creating any notification, so switching a
/// category off really stops it — including the email and SMS copies.
class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() => _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState extends State<NotificationPreferencesScreen> {
  NotificationPreferences? _prefs;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final prefs = await khejaApi.fetchNotificationPreferences();
      if (mounted) setState(() => _prefs = prefs);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  Future<void> _update(NotificationPreferences next) async {
    final previous = _prefs;
    setState(() {
      _prefs = next;
      _saving = true;
    });
    try {
      await khejaApi.saveNotificationPreferences(next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _prefs = previous);
      showKhejaSnack(context, describeError(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _prefs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification preferences'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 20),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: KhejaColors.blue),
                ),
              ),
            ),
        ],
      ),
      body: _error != null
          ? KhejaErrorState(message: _error!, onRetry: _load)
          : p == null
              ? const Center(child: CircularProgressIndicator(color: KhejaColors.blue))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  children: [
                    Text('What to tell me about', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 10),
                    _Switch(
                      icon: Icons.home_work_rounded,
                      title: 'Property availability alerts',
                      subtitle: 'A home you saved or are waiting for becomes available, and new matches.',
                      value: p.availabilityAlerts,
                      onChanged: (v) => _update(p.copyWith(availabilityAlerts: v)),
                    ),
                    _Switch(
                      icon: Icons.inbox_rounded,
                      title: 'Request updates',
                      subtitle: 'New requests, and when a request is viewed, accepted or declined.',
                      value: p.requestUpdates,
                      onChanged: (v) => _update(p.copyWith(requestUpdates: v)),
                    ),
                    const SizedBox(height: 22),
                    Text('How to reach me', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 10),
                    _Switch(
                      icon: Icons.notifications_rounded,
                      title: 'In-app notifications',
                      subtitle: 'In the Alerts tab. Payment and account notices always appear here.',
                      value: p.inApp,
                      onChanged: (v) => _update(p.copyWith(inApp: v)),
                    ),
                    _Switch(
                      icon: Icons.mail_rounded,
                      title: 'Email',
                      subtitle: 'To ${khejaApi.currentUser?.email ?? 'your account email'}.',
                      value: p.email,
                      onChanged: (v) => _update(p.copyWith(email: v)),
                    ),
                    _Switch(
                      icon: Icons.sms_rounded,
                      title: 'SMS',
                      subtitle: 'To the phone number on your profile. Kenyan numbers only.',
                      value: p.sms,
                      onChanged: (v) => _update(p.copyWith(sms: v)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Email and SMS are sent by Kheja_Link\'s server once those services are '
                      'switched on for your area; until then you get the in-app alert. We do '
                      'not place automated calls.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KhejaColors.zinc400, height: 1.5),
                    ),
                  ],
                ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: SwitchListTile(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.white,
          activeTrackColor: KhejaColors.blue,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KhejaRadius.lg)),
          secondary: Icon(icon, color: KhejaColors.blue),
          title: Text(title, style: theme.textTheme.titleMedium),
          subtitle: Text(
            subtitle,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KhejaColors.zinc500),
          ),
        ),
      ),
    );
  }
}
