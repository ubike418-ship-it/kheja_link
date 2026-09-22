import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';
import 'auth_screen.dart';
import 'hunting_screen.dart';
import 'inquiries_screen.dart';
import 'my_requests_screen.dart';
import 'notification_preferences_screen.dart';
import 'property_detail_screen.dart';
import 'request_sheet.dart';
import 'tenant_requests_screen.dart';

/// The Inbox: every notification Kheja_Link sends, in one place.
///
/// Everything here is written by the database: a saved home becoming
/// available, a new match, a request and its answer, a payment, a tenant
/// moving in or out. Each one respects the person's preferences before it is
/// created. This is the only place notifications go — Kheja_Link sends no
/// email or SMS — refreshed whenever the app is open.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<KhejaNotification>> _future;
  final Set<String> _readLocally = {};
  bool _isLandlord = false;
  String _filter = 'all';

  static const _filters = <({String id, String label})>[
    (id: 'all', label: 'All'),
    (id: 'unread', label: 'Unread'),
    (id: 'homes', label: 'Homes'),
    (id: 'requests', label: 'Requests'),
    (id: 'messages', label: 'Messages'),
    (id: 'payments', label: 'Payments'),
  ];

  bool _isRead(KhejaNotification n) => n.isRead || _readLocally.contains(n.id);

  bool _matches(KhejaNotification n) => switch (_filter) {
        'unread' => !_isRead(n),
        'homes' => const {'vacancy', 'match', 'listing_status'}.contains(n.type),
        'requests' => const {'request', 'booking', 'check_in', 'move_out'}.contains(n.type),
        'messages' => n.type == 'inquiry',
        'payments' => n.type == 'payment' || n.type == 'system',
        _ => true,
      };

  @override
  void initState() {
    super.initState();
    _future = khejaApi.fetchNotifications();
    khejaApi.fetchProfile().then((p) {
      if (mounted) setState(() => _isLandlord = p?.isLandlord ?? false);
    }).catchError((_) {});
  }

  Future<void> _refresh() async {
    final future = khejaApi.fetchNotifications();
    setState(() {
      _future = future;
      _readLocally.clear();
    });
    try {
      await future;
    } catch (_) {}
  }

  Future<void> _markAllRead() async {
    try {
      await khejaApi.markAllNotificationsRead();
      if (!mounted) return;
      showKhejaSnack(context, "You're all caught up.");
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _markRead(KhejaNotification n) async {
    if (n.isRead || _readLocally.contains(n.id)) return;
    setState(() => _readLocally.add(n.id));
    try {
      await khejaApi.markNotificationRead(n.id);
    } catch (_) {
      if (mounted) setState(() => _readLocally.remove(n.id));
    }
  }

  Future<String?> _slugFor(String propertyId) async {
    final slug = await khejaApi.fetchPropertySlug(propertyId);
    if (slug == null && mounted) {
      showKhejaSnack(context, 'That listing is no longer available.');
    }
    return slug;
  }

  Future<void> _openProperty(KhejaNotification n) async {
    _markRead(n);
    final id = n.propertyId;
    if (id == null) return;
    final slug = await _slugFor(id);
    if (slug == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PropertyDetailScreen(slug: slug)),
    );
  }

  Future<void> _requestHouse(KhejaNotification n) async {
    _markRead(n);
    final id = n.propertyId;
    if (id == null) return;
    final slug = await _slugFor(id);
    if (slug == null || !mounted) return;
    final property = await khejaApi.fetchPropertyBySlug(slug).catchError((_) => null);
    if (!mounted) return;
    if (property == null || !property.isRequestable) {
      showKhejaSnack(context, 'This home can no longer be requested. Opening it instead.');
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PropertyDetailScreen(slug: slug)),
      );
      return;
    }
    final sent = await showKhejaSheet<bool>(context, RequestSheet(property: property));
    if (sent == true && mounted) {
      showKhejaSnack(context, 'Request sent. The landlord has been notified.');
    }
  }

  void _openRequests(KhejaNotification n) {
    _markRead(n);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _isLandlord ? const TenantRequestsScreen() : const MyRequestsScreen(),
    ));
  }

  /// The main action a notification offers, if any.
  List<({String label, VoidCallback onTap, bool primary})> _actions(KhejaNotification n) {
    final hasProperty = n.propertyId != null;
    final fromLandlordSide = _isLandlord &&
        const {'request', 'inquiry', 'booking', 'check_in', 'move_out'}.contains(n.type);

    return switch (n.type) {
      'vacancy' || 'match' when hasProperty && n.title != 'Coming available' && n.title != 'Match coming available' => [
          (label: 'View property', onTap: () => _openProperty(n), primary: false),
          (label: 'Request house', onTap: () => _requestHouse(n), primary: true),
        ],
      'request' || 'booking' || 'check_in' || 'move_out' => [
          (label: fromLandlordSide ? 'View requests' : 'My requests', onTap: () => _openRequests(n), primary: true),
        ],
      'inquiry' when _isLandlord => [
          (
            label: 'Read message',
            onTap: () {
              _markRead(n);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InquiriesScreen()));
            },
            primary: true,
          ),
        ],
      'payment' => [
          (
            label: 'House Hunting',
            onTap: () {
              _markRead(n);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HuntingScreen()));
            },
            primary: true,
          ),
        ],
      _ when hasProperty => [(label: 'View property', onTap: () => _openProperty(n), primary: false)],
      _ => const [],
    };
  }

  @override
  Widget build(BuildContext context) {
    if (!khejaApi.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Inbox')),
        body: KhejaEmptyState(
          icon: Icons.inbox_rounded,
          title: 'Sign in to see your Inbox',
          message: 'We will tell you the moment a home you saved becomes available, and '
              'keep you posted on your requests.',
          actionLabel: 'Sign in',
          onAction: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
            if (mounted) _refresh();
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inbox'),
        actions: [
          TextButton(onPressed: _markAllRead, child: const Text('Mark all read')),
          IconButton(
            tooltip: 'Notification preferences',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationPreferencesScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: _refresh,
        child: FutureBuilder<List<KhejaNotification>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: KhejaColors.blue));
            }
            if (snapshot.hasError && !snapshot.hasData) {
              return ListView(children: [
                KhejaErrorState(message: describeError(snapshot.error!), onRetry: _refresh),
              ]);
            }

            final all = snapshot.data ?? const [];
            final items = all.where(_matches).toList();
            final unread = all.where((n) => !_isRead(n)).length;

            final header = Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    unread == 0
                        ? 'All your Kheja_Link notifications, in one place.'
                        : '$unread unread · all your Kheja_Link notifications, in one place.',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: KhejaColors.zinc500),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final f in _filters)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(f.id == 'unread' && unread > 0 ? 'Unread ($unread)' : f.label),
                              selected: _filter == f.id,
                              onSelected: (_) => setState(() => _filter = f.id),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );

            if (all.isNotEmpty && items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  header,
                  const KhejaEmptyState(
                    icon: Icons.filter_list_rounded,
                    title: 'Nothing here',
                    message: 'No notifications match this filter.',
                  ),
                ],
              );
            }

            if (items.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 60),
                  KhejaEmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: "You're all caught up",
                    message: 'Save a few homes, or ask to be notified about an occupied one, '
                        'and we will tell you when they become available.',
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: items.length + 1,
              separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 8 : 12),
              itemBuilder: (context, index) {
                if (index == 0) return header;
                final n = items[index - 1];
                final isRead = _isRead(n);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _NotificationTile(
                    item: n,
                    isRead: isRead,
                    actions: _actions(n),
                    onTap: () => n.propertyId != null ? _openProperty(n) : _markRead(n),
                    onMarkRead: isRead ? null : () => _markRead(n),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.isRead,
    required this.actions,
    required this.onTap,
    this.onMarkRead,
  });

  final KhejaNotification item;
  final bool isRead;
  final List<({String label, VoidCallback onTap, bool primary})> actions;
  final VoidCallback onTap;
  final VoidCallback? onMarkRead;

  static ({IconData icon, Color color}) _style(String type) => switch (type) {
        'vacancy' => (icon: Icons.celebration_rounded, color: KhejaColors.emerald),
        'match' => (icon: Icons.auto_awesome_rounded, color: KhejaColors.purple),
        'request' => (icon: Icons.inbox_rounded, color: KhejaColors.blue),
        'payment' => (icon: Icons.verified_rounded, color: KhejaColors.emerald),
        'inquiry' => (icon: Icons.mark_email_unread_rounded, color: KhejaColors.blue),
        'booking' => (icon: Icons.event_available_rounded, color: KhejaColors.purple),
        'check_in' => (icon: Icons.login_rounded, color: KhejaColors.emerald),
        'move_out' => (icon: Icons.logout_rounded, color: KhejaColors.amber),
        'listing_status' => (icon: Icons.home_work_rounded, color: KhejaColors.zinc500),
        _ => (icon: Icons.info_rounded, color: KhejaColors.blue),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _style(item.type);

    return Material(
      color: isRead ? theme.colorScheme.surface : KhejaColors.blue.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(KhejaRadius.xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 10, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.xl),
            border: Border.all(
              color: isRead ? theme.colorScheme.outline : KhejaColors.blue.withValues(alpha: 0.45),
              width: isRead ? 1 : 1.4,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: style.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(KhejaRadius.md),
                ),
                child: Icon(style.icon, size: 20, color: style.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: isRead ? FontWeight.w700 : FontWeight.w900,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: KhejaColors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    if (item.body != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.body!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: KhejaColors.zinc500,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatRelativeDate(item.createdAt).toUpperCase(),
                            style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
                          ),
                        ),
                        if (onMarkRead != null)
                          TextButton(
                            onPressed: onMarkRead,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                            child: const Text('Mark as read'),
                          ),
                      ],
                    ),
                    if (actions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in actions)
                            a.primary
                                ? FilledButton(
                                    onPressed: a.onTap,
                                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                    child: Text(a.label),
                                  )
                                : OutlinedButton(
                                    onPressed: a.onTap,
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                                    child: Text(a.label),
                                  ),
                        ],
                      ),
                    ],
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
