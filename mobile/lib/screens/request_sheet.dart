import 'package:flutter/material.dart';

import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';

/// "Request this house": tells the landlord you want it, with when you would
/// like to move in. Not a payment and not a booking — the landlord accepts or
/// declines, and both sides are notified by the database.
class RequestSheet extends StatefulWidget {
  const RequestSheet({super.key, required this.property});

  final Property property;

  @override
  State<RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<RequestSheet> {
  final _note = TextEditingController();
  DateTime? _moveIn;
  bool _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    try {
      await khejaApi.requestProperty(
        widget.property.id,
        note: _note.text,
        preferredMoveIn: _moveIn,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();

    return KhejaSheet(
      title: 'Request this house',
      subtitle: 'The landlord of ${widget.property.title} will see your request and '
          'can accept or decline it. This is not a payment.',
      actionLabel: 'Send request',
      busy: _sending,
      onAction: _send,
      children: [
        DateField(
          label: 'Preferred move-in date (optional)',
          value: _moveIn,
          clearable: true,
          firstDate: DateTime(today.year, today.month, today.day),
          lastDate: today.add(const Duration(days: 365)),
          onChanged: (d) => setState(() => _moveIn = d),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(
            labelText: 'Message to the landlord (optional)',
            hintText: 'e.g. Can I view it on Saturday?',
          ),
        ),
      ],
    );
  }
}
