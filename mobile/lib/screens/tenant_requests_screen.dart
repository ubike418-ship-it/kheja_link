import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';
import 'auth_screen.dart';
import 'my_requests_screen.dart' show RequestStatusPill;
import 'property_detail_screen.dart';

/// Requests from tenants across every one of the landlord's homes.
///
/// The tenant's name is always shown; their phone number only appears once the
/// landlord accepts — the database, not this screen, decides that.
class TenantRequestsScreen extends StatefulWidget {
  const TenantRequestsScreen({super.key, this.propertyId, this.isRoot = false});

  /// Show only one home's requests ("View requests" on a listing).
  final String? propertyId;

  /// True when this is a tab rather than a pushed page.
  final bool isRoot;

  @override
  State<TenantRequestsScreen> createState() => _TenantRequestsScreenState();
}

const _filters = <({String value, String label})>[
  (value: 'open', label: 'Open'),
  (value: 'accepted', label: 'Accepted'),
  (value: 'closed', label: 'Closed'),
  (value: 'all', label: 'All'),
];

class _TenantRequestsScreenState extends State<TenantRequestsScreen> {
  late Future<List<OwnerRequest>> _future;
  String _filter = 'open';
  final Set<String> _busy = {};

  /// Requests opened in this session, shown as viewed without a reload (a
  /// reload would collapse the card being read).
  final Set<String> _seen = {};

  @override
  void initState() {
    super.initState();
    _future = khejaApi.fetchRequestsForOwner();
  }

  Future<void> _refresh() async {
    final future = khejaApi.fetchRequestsForOwner();
    setState(() => _future = future);
    try {
      await future;
    } catch (_) {}
  }

  bool _matches(OwnerRequest r) {
    if (widget.propertyId != null && r.propertyId != widget.propertyId) return false;
    return switch (_filter) {
      'open' => r.isOpen,
      'accepted' => r.status == 'accepted' || r.status == 'checked_in',
      'closed' => const {'declined', 'cancelled', 'moved_out'}.contains(r.status),
      _ => true,
    };
  }

  Future<void> _set(OwnerRequest r, String status, {String? response, String? done}) async {
    setState(() => _busy.add(r.id));
    try {
      await khejaApi.setTenancyStatus(r.id, status, landlordResponse: response);
      if (!mounted) return;
      if (done != null) showKhejaSnack(context, done);
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  /// Opening a pending request tells the tenant it has been seen. Quietly:
  /// if it fails, nothing the landlord is doing is affected.
  Future<void> _view(OwnerRequest r) async {
    if (r.status != 'booked' || _seen.contains(r.id)) return;
    setState(() => _seen.add(r.id));
    try {
      await khejaApi.setTenancyStatus(r.id, 'viewed');
    } catch (_) {
      if (mounted) setState(() => _seen.remove(r.id));
    }
  }

  Future<void> _respond(OwnerRequest r, {required bool accept}) async {
    final response = await showKhejaSheet<String>(
      context,
      _RespondSheet(request: r, accept: accept),
    );
    if (response == null || !mounted) return;
    await _set(
      r,
      accept ? 'accepted' : 'declined',
      response: response,
      done: accept
          ? 'Accepted. ${r.tenantName} has been notified — their number is now shown.'
          : 'Declined. ${r.tenantName} has been notified.',
    );
  }

  Future<void> _call(String phone) async {
    final ok = await launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);
    if (!ok && mounted) showKhejaSnack(context, 'Could not start a call.', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!khejaApi.isSignedIn) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.isRoot,
          title: const Text('Tenant Requests'),
        ),
        body: KhejaEmptyState(
          icon: Icons.inbox_rounded,
          title: 'Sign in to see requests',
          message: 'Requests from tenants for your homes appear here once you sign in as a landlord.',
          actionLabel: 'Sign in as landlord',
          onAction: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AuthScreen(role: 'landlord')),
            );
            if (mounted) _refresh();
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.isRoot,
        title: Text(widget.propertyId == null ? 'Tenant Requests' : 'Requests for this home'),
      ),
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: _refresh,
        child: FutureBuilder<List<OwnerRequest>>(
          future: _future,
          builder: (context, snapshot) {
            // Keep showing the last list while a refresh is in flight.
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: KhejaColors.blue));
            }
            if (snapshot.hasError && !snapshot.hasData) {
              return ListView(children: [
                KhejaErrorState(message: describeError(snapshot.error!), onRetry: _refresh),
              ]);
            }

            final all = snapshot.data ?? const [];
            final items = all
                .map((r) => r.status == 'booked' && _seen.contains(r.id) ? r.withStatus('viewed') : r)
                .where(_matches)
                .toList();

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.label),
                            selected: _filter == f.value,
                            onSelected: (_) => setState(() => _filter = f.value),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (items.isEmpty)
                  KhejaEmptyState(
                    icon: Icons.inbox_rounded,
                    title: all.isEmpty ? 'No tenant requests yet' : 'Nothing here',
                    message: all.isEmpty
                        ? 'When a tenant requests one of your homes it appears here, and you get a notification.'
                        : 'No requests match this filter.',
                  )
                else
                  for (final r in items)
                    Padding(
                      key: ValueKey(r.id),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RequestTile(
                        request: r,
                        busy: _busy.contains(r.id),
                        onView: () => _view(r),
                        onAccept: () => _respond(r, accept: true),
                        onDecline: () => _respond(r, accept: false),
                        onCall: r.tenantPhone == null ? null : () => _call(r.tenantPhone!),
                        onOpenHome: r.propertySlug.isEmpty
                            ? null
                            : () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => PropertyDetailScreen(slug: r.propertySlug))),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.busy,
    required this.onView,
    required this.onAccept,
    required this.onDecline,
    this.onCall,
    this.onOpenHome,
  });

  final OwnerRequest request;
  final bool busy;
  final VoidCallback onView;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback? onCall;
  final VoidCallback? onOpenHome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(
          color: r.status == 'booked'
              ? KhejaColors.amber.withValues(alpha: 0.5)
              : theme.colorScheme.outline,
          width: r.status == 'booked' ? 1.4 : 1,
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          onExpansionChanged: (open) {
            if (open) onView();
          },
          leading: CircleAvatar(
            backgroundColor: KhejaColors.blue.withValues(alpha: 0.12),
            child: Text(
              r.tenantName.isEmpty ? '?' : r.tenantName[0].toUpperCase(),
              style: const TextStyle(color: KhejaColors.blue, fontWeight: FontWeight.w900),
            ),
          ),
          title: Text(r.tenantName, style: theme.textTheme.titleMedium),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.propertyTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: KhejaColors.zinc500),
                ),
                const SizedBox(height: 6),
                RequestStatusPill(r.status),
              ],
            ),
          ),
          children: [
            _Row('Property type', r.propertyType ?? '—'),
            _Row('Requested', r.bookedAt == null ? '—' : formatShortDate(r.bookedAt!)),
            _Row('Preferred move-in', r.preferredMoveIn == null ? 'Not given' : formatShortDate(r.preferredMoveIn!)),
            if (r.note != null && r.note!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(KhejaRadius.md),
                ),
                child: Text('"${r.note!.trim()}"',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
              ),
            ],
            if (r.landlordResponse != null && r.landlordResponse!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Your reply: "${r.landlordResponse!.trim()}"',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: KhejaColors.zinc500)),
            ],
            const SizedBox(height: 12),
            if (busy)
              const Center(child: CircularProgressIndicator(color: KhejaColors.blue))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (r.isOpen) ...[
                    FilledButton.icon(
                      onPressed: onAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: KhejaColors.emerald,
                        minimumSize: const Size(0, 44),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accept'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: KhejaColors.red,
                        minimumSize: const Size(0, 44),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Decline'),
                    ),
                  ],
                  if (r.status == 'accepted')
                    OutlinedButton(
                      onPressed: onDecline,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      child: const Text('Withdraw acceptance'),
                    ),
                  if (onCall != null)
                    FilledButton.icon(
                      onPressed: onCall,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text('Call tenant'),
                    ),
                  if (onOpenHome != null)
                    TextButton(onPressed: onOpenHome, child: const Text('View home')),
                ],
              ),
            if (r.isOpen)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  "The tenant's phone number is shared with you once you accept.",
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: KhejaColors.zinc400),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label.toUpperCase(), style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}

/// Accept or decline, with an optional message for the tenant.
class _RespondSheet extends StatefulWidget {
  const _RespondSheet({required this.request, required this.accept});

  final OwnerRequest request;
  final bool accept;

  @override
  State<_RespondSheet> createState() => _RespondSheetState();
}

class _RespondSheetState extends State<_RespondSheet> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accept = widget.accept;
    return KhejaSheet(
      title: accept ? 'Accept this request?' : 'Decline this request?',
      subtitle: accept
          ? '${widget.request.tenantName} will be notified and you will see their phone '
              'number so you can arrange a viewing or the move.'
          : '${widget.request.tenantName} will be notified. You can add a short, polite reason.',
      actionLabel: accept ? 'Accept request' : 'Decline request',
      actionColor: accept ? KhejaColors.emerald : KhejaColors.red,
      onAction: () => Navigator.of(context).pop(_message.text.trim()),
      children: [
        TextField(
          controller: _message,
          maxLines: 3,
          maxLength: 1000,
          decoration: InputDecoration(
            labelText: 'Message to the tenant (optional)',
            hintText: accept
                ? 'e.g. Come and view on Saturday at 10am.'
                : 'e.g. Sorry, it has been taken.',
          ),
        ),
      ],
    );
  }
}
