import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/states.dart';

/// A landlord's leads. RLS restricts SELECT on `inquiries` to the listing's
/// owner and the original sender, so this can never show another landlord's.
class InquiriesScreen extends StatefulWidget {
  const InquiriesScreen({super.key});

  @override
  State<InquiriesScreen> createState() => _InquiriesScreenState();
}

const _filters = <({String value, String label})>[
  (value: 'all', label: 'All'),
  (value: 'new', label: 'New'),
  (value: 'read', label: 'Read'),
  (value: 'responded', label: 'Responded'),
  (value: 'closed', label: 'Closed'),
];

class _InquiriesScreenState extends State<InquiriesScreen> {
  late Future<List<Inquiry>> _future;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = khejaApi.fetchInquiriesForOwner();
  }

  Future<void> _refresh() async {
    final future = khejaApi.fetchInquiriesForOwner();
    setState(() => _future = future);
    await future;
  }

  Future<void> _setStatus(Inquiry inquiry, String status) async {
    try {
      await khejaApi.updateInquiryStatus(inquiry.id, status);
      if (!mounted) return;
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Future<void> _launch(Uri uri, String failure) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showKhejaSnack(context, failure, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inquiries')),
      body: RefreshIndicator(
        color: KhejaColors.blue,
        onRefresh: _refresh,
        child: FutureBuilder<List<Inquiry>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: KhejaColors.blue),
              );
            }

            if (snapshot.hasError) {
              return KhejaErrorState(
                message: describeError(snapshot.error!),
                onRetry: _refresh,
              );
            }

            final all = snapshot.data ?? const <Inquiry>[];
            final visible =
                _filter == 'all' ? all : all.where((i) => i.status == _filter).toList();

            return Column(
              children: [
                SizedBox(
                  height: 62,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                    itemCount: _filters.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final option = _filters[index];
                      final count = option.value == 'all'
                          ? all.length
                          : all.where((i) => i.status == option.value).length;
                      final selected = _filter == option.value;

                      return _FilterChip(
                        label: option.label,
                        count: count,
                        selected: selected,
                        onTap: () => setState(() => _filter = option.value),
                      );
                    },
                  ),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 40),
                            KhejaEmptyState(
                              icon: Icons.mark_email_unread_rounded,
                              title: all.isEmpty
                                  ? 'No inquiries yet'
                                  : 'Nothing with that status',
                              message: all.isEmpty
                                  ? 'Once your listings are published, people who '
                                      'ask about them will appear here.'
                                  : 'Try another filter.',
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (context, index) => _InquiryCard(
                            inquiry: visible[index],
                            onStatusChanged: (status) =>
                                _setStatus(visible[index], status),
                            onLaunch: _launch,
                          ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? theme.colorScheme.onSurface : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.md),
            border: Border.all(
              color: selected ? Colors.transparent : theme.colorScheme.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color:
                      selected ? theme.colorScheme.surface : KhejaColors.zinc500,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: selected
                      ? theme.colorScheme.surface.withValues(alpha: 0.7)
                      : KhejaColors.zinc400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InquiryCard extends StatelessWidget {
  const _InquiryCard({
    required this.inquiry,
    required this.onStatusChanged,
    required this.onLaunch,
  });

  final Inquiry inquiry;
  final ValueChanged<String> onStatusChanged;
  final Future<void> Function(Uri, String) onLaunch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = inquiry.status == 'new';
    final phoneDigits = inquiry.phone?.replaceAll(RegExp(r'[^\d+]'), '');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(
          color: isNew ? KhejaColors.blue.withValues(alpha: 0.5) : theme.colorScheme.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  inquiry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                formatRelativeDate(inquiry.createdAt),
                style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
              ),
            ],
          ),
          if (inquiry.propertyTitle != null) ...[
            const SizedBox(height: 4),
            Text(
              inquiry.propertyTitle!.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kEyebrowStyle.copyWith(color: KhejaColors.blue),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            inquiry.message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: KhejaColors.zinc500, height: 1.55),
          ),
          const SizedBox(height: 16),
          Divider(color: theme.colorScheme.outline, height: 1),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (inquiry.email != null)
                _Action(
                  icon: Icons.mail_rounded,
                  label: 'Email',
                  filled: true,
                  onTap: () => onLaunch(
                    Uri.parse(
                      'mailto:${inquiry.email}'
                      '?subject=${Uri.encodeComponent('Re: ${inquiry.propertyTitle ?? 'your Kheja_Link inquiry'}')}',
                    ),
                    'No email app is set up on this device.',
                  ),
                ),
              if (phoneDigits != null && phoneDigits.isNotEmpty)
                _Action(
                  icon: Icons.phone_rounded,
                  label: inquiry.phone!,
                  onTap: () => onLaunch(
                    Uri.parse('tel:$phoneDigits'),
                    'Could not start a call on this device.',
                  ),
                ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: inquiry.status,
                  isDense: true,
                  decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'new', child: Text('New')),
                    DropdownMenuItem(value: 'read', child: Text('Read')),
                    DropdownMenuItem(value: 'responded', child: Text('Responded')),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  onChanged: (value) {
                    if (value != null && value != inquiry.status) {
                      onStatusChanged(value);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: filled ? theme.colorScheme.onSurface : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.md),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.md),
            border: Border.all(
              color: filled ? Colors.transparent : theme.colorScheme.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: filled
                      ? theme.colorScheme.surface
                      : theme.colorScheme.onSurface),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: filled
                      ? theme.colorScheme.surface
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
