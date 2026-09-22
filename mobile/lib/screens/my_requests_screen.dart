import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';
import 'alert_sheet.dart';
import 'auth_screen.dart';
import 'property_detail_screen.dart';

/// A tenant's house requests and everything they are waiting on.
///
///   Requests    homes they asked for, the landlord's answer, and next steps
///   Waiting for "notify me" on occupied homes, and standing search alerts
///
/// Landlord details never appear here: the landlord's reply is shown, their
/// contact details stay behind the listing's unlock.
class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  late Future<List<Tenancy>> _requests;
  late Future<List<PropertyInterest>> _interests;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _requests = khejaApi.fetchMyTenancies();
    _interests = khejaApi.fetchMyInterests();
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await Future.wait<Object>([_requests, _interests]);
    } catch (_) {
      // Each tab shows its own error state.
    }
  }

  void _openProperty(String? slug) {
    if (slug == null || slug.isEmpty) {
      showKhejaSnack(context, 'That listing is no longer available to view.');
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PropertyDetailScreen(slug: slug)))
        .then((_) => _refresh());
  }

  Future<void> _setStatus(Tenancy t, String status, String done) async {
    try {
      await khejaApi.setTenancyStatus(t.id, status);
      if (!mounted) return;
      showKhejaSnack(context, done);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _withdraw(Tenancy t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KhejaRadius.lg)),
        title: const Text('Withdraw this request?'),
        content: Text('The landlord of ${t.propertyTitle ?? 'this home'} will be told.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: KhejaColors.red),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok == true) await _setStatus(t, 'cancelled', 'Request withdrawn.');
  }

  Future<void> _cancelInterest(PropertyInterest i) async {
    try {
      await khejaApi.cancelInterest(i.id);
      if (!mounted) return;
      showKhejaSnack(context, 'You will no longer be notified about this.');
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _newAlert() async {
    final saved = await showKhejaSheet<bool>(context, const SearchAlertSheet());
    if (saved == true && mounted) {
      showKhejaSnack(context, 'Alert saved. We will tell you when a match is available.');
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!khejaApi.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Requests')),
        body: KhejaEmptyState(
          icon: Icons.inbox_rounded,
          title: 'Sign in to see your requests',
          message: 'Requests you send, homes you are waiting on and your alerts all live here.',
          actionLabel: 'Sign in',
          onAction: () async {
            await Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AuthScreen(role: 'seeker')));
            if (mounted) setState(_load);
          },
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Requests'),
          bottom: const TabBar(
            labelStyle: TextStyle(fontWeight: FontWeight.w900),
            tabs: [Tab(text: 'Requests'), Tab(text: 'Waiting for')],
          ),
        ),
        body: TabBarView(
          children: [
            _RequestsTab(
              future: _requests,
              onRefresh: _refresh,
              onOpen: _openProperty,
              onWithdraw: _withdraw,
              onMovedIn: (t) => _setStatus(t, 'checked_in', 'Welcome home! The landlord has been told.'),
              onMovedOut: (t) => _setStatus(t, 'moved_out', 'Moved out. The landlord has been told.'),
            ),
            _WaitingTab(
              future: _interests,
              onRefresh: _refresh,
              onOpen: (i) => _openProperty(i.property?.slug),
              onCancel: _cancelInterest,
              onNewAlert: _newAlert,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({
    required this.future,
    required this.onRefresh,
    required this.onOpen,
    required this.onWithdraw,
    required this.onMovedIn,
    required this.onMovedOut,
  });

  final Future<List<Tenancy>> future;
  final Future<void> Function() onRefresh;
  final void Function(String? slug) onOpen;
  final void Function(Tenancy) onWithdraw;
  final void Function(Tenancy) onMovedIn;
  final void Function(Tenancy) onMovedOut;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: KhejaColors.blue,
      onRefresh: onRefresh,
      child: FutureBuilder<List<Tenancy>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: KhejaColors.blue));
          }
          if (snapshot.hasError) {
            return ListView(children: [
              KhejaErrorState(message: describeError(snapshot.error!), onRetry: onRefresh),
            ]);
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 40),
                KhejaEmptyState(
                  icon: Icons.inbox_rounded,
                  title: "You don't have any active house requests",
                  message: 'Open a home that is available now and tap "Request this house".',
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _RequestCard(
              tenancy: items[i],
              onOpen: () => onOpen(items[i].propertySlug),
              onWithdraw: () => onWithdraw(items[i]),
              onMovedIn: () => onMovedIn(items[i]),
              onMovedOut: () => onMovedOut(items[i]),
            ),
          );
        },
      ),
    );
  }
}

Color requestStatusColor(String status) => switch (status) {
      'booked' => KhejaColors.amber,
      'viewed' => KhejaColors.blue,
      'accepted' || 'checked_in' => KhejaColors.emerald,
      'declined' => KhejaColors.red,
      _ => KhejaColors.zinc400,
    };

class RequestStatusPill extends StatelessWidget {
  const RequestStatusPill(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = requestStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KhejaRadius.sm),
      ),
      child: Text(
        tenancyStatusLabel(status).toUpperCase(),
        style: kEyebrowStyle.copyWith(color: color, letterSpacing: 1.2),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.tenancy,
    required this.onOpen,
    required this.onWithdraw,
    required this.onMovedIn,
    required this.onMovedOut,
  });

  final Tenancy tenancy;
  final VoidCallback onOpen;
  final VoidCallback onWithdraw;
  final VoidCallback onMovedIn;
  final VoidCallback onMovedOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = tenancy;

    final next = switch (t.status) {
      'booked' => 'Waiting for the landlord to respond.',
      'viewed' => 'The landlord has seen your request.',
      'accepted' => 'Accepted. Arrange the move with the landlord, then tell us when you move in.',
      'declined' => 'Not accepted this time. Keep browsing — or set an alert.',
      'checked_in' => 'You are living here.',
      'moved_out' => 'You moved out.',
      _ => 'You withdrew this request.',
    };

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.xl),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
            border: Border.all(color: theme.colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      t.propertyTitle ?? 'A listing',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  RequestStatusPill(t.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (t.bookedAt != null) 'Requested ${formatRelativeDate(t.bookedAt).toLowerCase()}',
                  if (t.preferredMoveIn != null) 'move-in ${formatShortDate(t.preferredMoveIn!)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: KhejaColors.zinc500),
              ),
              const SizedBox(height: 8),
              Text(next, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
              if (t.landlordResponse != null && t.landlordResponse!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KhejaColors.blue.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(KhejaRadius.md),
                  ),
                  child: Text(
                    'Landlord: "${t.landlordResponse!.trim()}"',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                  ),
                ),
              ],
              if (t.status == 'accepted' || t.status == 'checked_in' || t.canWithdraw) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (t.status == 'accepted')
                      FilledButton.icon(
                        onPressed: onMovedIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: KhejaColors.emerald,
                          minimumSize: const Size(0, 44),
                        ),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text('I have moved in'),
                      ),
                    if (t.status == 'checked_in')
                      OutlinedButton.icon(
                        onPressed: onMovedOut,
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('I have moved out'),
                      ),
                    if (t.canWithdraw)
                      TextButton(
                        onPressed: onWithdraw,
                        style: TextButton.styleFrom(foregroundColor: KhejaColors.red),
                        child: const Text('Withdraw'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingTab extends StatelessWidget {
  const _WaitingTab({
    required this.future,
    required this.onRefresh,
    required this.onOpen,
    required this.onCancel,
    required this.onNewAlert,
  });

  final Future<List<PropertyInterest>> future;
  final Future<void> Function() onRefresh;
  final void Function(PropertyInterest) onOpen;
  final void Function(PropertyInterest) onCancel;
  final VoidCallback onNewAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      color: KhejaColors.blue,
      onRefresh: onRefresh,
      child: FutureBuilder<List<PropertyInterest>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: KhejaColors.blue));
          }
          if (snapshot.hasError) {
            return ListView(children: [
              KhejaErrorState(message: describeError(snapshot.error!), onRetry: onRefresh),
            ]);
          }
          final all = snapshot.data ?? const [];
          final homes = all.where((i) => i.isForProperty).toList();
          final alerts = all.where((i) => !i.isForProperty).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              OutlinedButton.icon(
                onPressed: onNewAlert,
                icon: const Icon(Icons.add_alert_rounded, size: 20),
                label: const Text('Notify me about new homes'),
              ),
              const SizedBox(height: 22),
              Text('Homes you are waiting for', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (homes.isEmpty)
                const _Hint(
                  icon: Icons.notifications_none_rounded,
                  text: 'See a home that is occupied? Tap "Notify me when available" on it '
                      'and it will appear here.',
                )
              else
                for (final i in homes)
                  _InterestTile(
                    title: i.property?.title ?? 'A listing',
                    subtitle: i.isActive
                        ? (i.property?.availabilityLabel ?? 'Available now — open it to request')
                        : 'You were notified ${formatRelativeDate(i.lastNotifiedAt).toLowerCase()}',
                    icon: i.isActive ? Icons.hourglass_top_rounded : Icons.notifications_active_rounded,
                    color: i.isActive ? KhejaColors.purple : KhejaColors.emerald,
                    onTap: () => onOpen(i),
                    onCancel: i.isActive ? () => onCancel(i) : null,
                  ),
              const SizedBox(height: 22),
              Text('Your alerts', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              if (alerts.isEmpty)
                const _Hint(
                  icon: Icons.manage_search_rounded,
                  text: 'No alerts yet. Set one and we will tell you when a matching home '
                      'becomes available — for example, a one-bedroom in Makutano.',
                )
              else
                for (final a in alerts)
                  _InterestTile(
                    title: a.summary,
                    subtitle: a.lastNotifiedAt == null
                        ? 'No matches yet'
                        : 'Last match ${formatRelativeDate(a.lastNotifiedAt).toLowerCase()}',
                    icon: Icons.manage_search_rounded,
                    color: KhejaColors.blue,
                    onCancel: () => onCancel(a),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _InterestTile extends StatelessWidget {
  const _InterestTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.onCancel,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(KhejaRadius.lg),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(KhejaRadius.sm),
                  ),
                  child: Icon(icon, size: 19, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: KhejaColors.zinc500)),
                    ],
                  ),
                ),
                if (onCancel != null)
                  IconButton(
                    onPressed: onCancel,
                    tooltip: 'Stop notifying me',
                    icon: const Icon(Icons.notifications_off_outlined, size: 20),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.lg),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: KhejaColors.zinc300),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: KhejaColors.zinc500, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
