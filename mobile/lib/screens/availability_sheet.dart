import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';

/// The landlord's "Set availability".
///
///   Available now               tenants can request it today
///   Available on a future date  occupied, free from a date — "coming available"
///   Occupied                    no date yet
///   Temporarily unavailable     repairs and the like
///
/// The home stays listed in every state, so tenants can ask to be told when it
/// frees up. When it becomes available, the database notifies everyone waiting.
class AvailabilitySheet extends StatefulWidget {
  const AvailabilitySheet({super.key, required this.property});

  final Property property;

  @override
  State<AvailabilitySheet> createState() => _AvailabilitySheetState();
}

class _AvailabilitySheetState extends State<AvailabilitySheet> {
  late String _choice = widget.property.availability;
  late DateTime? _from = widget.property.availableFrom;
  late DateTime? _notice = widget.property.noticeDate;
  bool _saving = false;
  String? _dateError;

  static const _options = <({String value, String label, String hint, IconData icon})>[
    (
      value: 'available',
      label: 'Available now',
      hint: 'Tenants can request it today.',
      icon: Icons.check_circle_rounded,
    ),
    (
      value: 'notice_given',
      label: 'Available on a future date',
      hint: 'Shown as "Available from…" so tenants can ask to be notified.',
      icon: Icons.event_rounded,
    ),
    (
      value: 'occupied',
      label: 'Occupied',
      hint: 'Someone lives there and you do not know when it frees up.',
      icon: Icons.meeting_room_rounded,
    ),
    (
      value: 'unavailable',
      label: 'Temporarily unavailable',
      hint: 'Off the market for now, e.g. repairs.',
      icon: Icons.pause_circle_rounded,
    ),
  ];

  Future<void> _save() async {
    final today = DateTime.now();
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    if (_choice == 'notice_given') {
      if (_from == null) {
        setState(() => _dateError = 'Choose the date it becomes available');
        return;
      }
      if (_from!.isBefore(tomorrow)) {
        setState(() => _dateError = 'Pick a date after today, or choose "Available now"');
        return;
      }
    }

    setState(() {
      _saving = true;
      _dateError = null;
    });
    try {
      await khejaApi.setPropertyAvailability(
        widget.property.id,
        availability: _choice,
        availableFrom: _from,
        noticeDate: _notice,
        republish: widget.property.status == 'rented',
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();

    return KhejaSheet(
      title: 'Set availability',
      subtitle: widget.property.title,
      actionLabel: 'Save availability',
      busy: _saving,
      onAction: _save,
      children: [
        if (widget.property.status == 'rented')
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'This listing is marked rented and hidden from tenants. Saving puts it '
              'back on Kheja_Link with the availability you choose here.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: KhejaColors.amber, height: 1.45),
            ),
          )
        else if (widget.property.status != 'published')
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Text(
              'This listing is not published, so tenants will not see it until you publish it.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: KhejaColors.amber, height: 1.45),
            ),
          ),
        for (final o in _options)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(KhejaRadius.lg),
              child: InkWell(
                borderRadius: BorderRadius.circular(KhejaRadius.lg),
                onTap: () => setState(() {
                  _choice = o.value;
                  _dateError = null;
                }),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(KhejaRadius.lg),
                    border: Border.all(
                      color: _choice == o.value ? KhejaColors.blue : theme.colorScheme.outline,
                      width: _choice == o.value ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(o.icon,
                          color: _choice == o.value ? KhejaColors.blue : KhejaColors.zinc400),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.label, style: theme.textTheme.titleMedium),
                            Text(
                              o.hint,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: KhejaColors.zinc500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _choice == o.value
                            ? Icons.radio_button_checked_rounded
                            : Icons.radio_button_off_rounded,
                        color: _choice == o.value ? KhejaColors.blue : KhejaColors.zinc300,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_choice == 'notice_given') ...[
          const SizedBox(height: 6),
          DateField(
            label: 'Available from',
            value: _from,
            errorText: _dateError,
            firstDate: DateTime(today.year, today.month, today.day + 1),
            lastDate: today.add(const Duration(days: 730)),
            onChanged: (d) => setState(() {
              _from = d;
              _dateError = null;
            }),
          ),
          const SizedBox(height: 12),
          DateField(
            label: 'Notice received on (optional)',
            value: _notice,
            clearable: true,
            placeholder: 'When the tenant gave notice',
            firstDate: today.subtract(const Duration(days: 365)),
            lastDate: DateTime(today.year, today.month, today.day),
            onChanged: (d) => setState(() => _notice = d),
          ),
          const SizedBox(height: 10),
          const Text(
            'On that date the listing switches to "Available now" automatically and '
            'everyone waiting is notified. You can change it any time.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KhejaColors.zinc500, height: 1.45),
          ),
        ],
        if (_choice == 'available' && widget.property.availability != 'available')
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Tenants who saved this home or asked to be notified will be told it is available.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: KhejaColors.emerald, height: 1.45),
            ),
          ),
      ],
    );
  }
}
