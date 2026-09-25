import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';

/// "Give us a house": a vacant home the tenant knows of — the one they are
/// leaving, or one whose landlord agrees to list with Kheja_Link.
///
/// The tenant only describes the house. Whether a refund applies, and every
/// step after that, is decided by the database and an admin, and reported in
/// the tenant's Inbox.
class GiveHouseSheet extends StatefulWidget {
  const GiveHouseSheet({super.key, required this.settings, this.showRefund = false});

  final BusinessSettings settings;

  /// Only for a tenant who has paid for an unlock: they already know the price,
  /// so the refund amount can be named.
  final bool showRefund;

  @override
  State<GiveHouseSheet> createState() => _GiveHouseSheetState();
}

class _GiveHouseSheetState extends State<GiveHouseSheet> {
  List<PropertyType> _types = const [];
  List<KhejaLocation> _locations = const [];
  bool _loadingLists = true;
  String? _listError;

  String _relationship = 'moving_out';
  String? _typeId;
  String? _locationId;
  int? _bedrooms;
  DateTime? _availableFrom;
  final _area = TextEditingController();
  final _rent = TextEditingController();
  final _landlordName = TextEditingController();
  final _landlordPhone = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  @override
  void dispose() {
    for (final c in [_area, _rent, _landlordName, _landlordPhone, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLists() async {
    setState(() {
      _loadingLists = true;
      _listError = null;
    });
    try {
      final results = await Future.wait([
        khejaApi.fetchPropertyTypes(),
        khejaApi.fetchLocations(),
      ]);
      if (!mounted) return;
      setState(() {
        _types = results[0] as List<PropertyType>;
        _locations = results[1] as List<KhejaLocation>;
        _loadingLists = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingLists = false;
        _listError = describeError(error);
      });
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _availableFrom ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _availableFrom = picked);
  }

  Future<void> _save() async {
    final phone = _landlordPhone.text.replaceAll(RegExp(r'[\s-]'), '');
    if (_locationId == null && _area.text.trim().isEmpty) {
      setState(() => _error = 'Choose the area or describe where the house is.');
      return;
    }
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(phone)) {
      setState(() => _error = 'Enter the landlord\'s phone number, e.g. 0712 345 678.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await khejaApi.submitHouse(
        relationship: _relationship,
        locationId: _locationId,
        area: _area.text,
        propertyTypeId: _typeId,
        bedrooms: _bedrooms,
        rentAmount: num.tryParse(_rent.text.trim()),
        availableFrom: _availableFrom,
        landlordName: _landlordName.text,
        landlordPhone: phone,
        notes: _notes.text,
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
    final s = widget.settings;

    return KhejaSheet(
      title: 'Give us a house',
      subtitle: s.refundsEnabled && widget.showRefund
          ? 'Tell us about a vacant house. Once we approve it, ${s.refundLabel} of your '
              '${s.unlockFeeLabel} unlock comes back to you — one refund per unlock.'
          : 'Tell us about a vacant house and we will check it with the landlord.',
      actionLabel: 'Send house',
      busy: _saving || _loadingLists,
      onAction: _listError == null ? _save : _loadLists,
      children: [
        if (_listError != null) ...[
          Text(_listError!, style: const TextStyle(color: KhejaColors.red, fontWeight: FontWeight.w700)),
          TextButton(onPressed: _loadLists, child: const Text('Try again')),
        ] else if (_loadingLists)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator(color: KhejaColors.blue)),
          )
        else ...[
          Text('THE HOUSE IS', style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in const [
                ('moving_out', 'The one I am moving out of'),
                ('landlord_agrees', 'A landlord wants to list it'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _relationship == value,
                  onSelected: (_) => setState(() => _relationship = value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          DropdownButtonFormField<String?>(
            initialValue: _locationId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Area'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Choose an area')),
              for (final l in _locations) DropdownMenuItem(value: l.id, child: Text(l.name)),
            ],
            onChanged: (v) => setState(() => _locationId = v),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _area,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Estate, road or landmark',
              counterText: '',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: _typeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Property type'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Not sure')),
              for (final t in _types) DropdownMenuItem(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => _typeId = v),
          ),
          const SizedBox(height: 18),
          Text('BEDROOMS', style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (value, label) in const [
                (null, 'Not sure'),
                (0, 'Bedsitter'),
                (1, '1'),
                (2, '2'),
                (3, '3'),
                (4, '4+'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _bedrooms == value,
                  onSelected: (_) => setState(() => _bedrooms = value),
                ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _rent,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Monthly rent (KSh), if you know it'),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_rounded, size: 18),
            label: Text(_availableFrom == null
                ? 'Free from (optional)'
                : 'Free from ${DateFormat('d MMM yyyy').format(_availableFrom!)}'),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _landlordName,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Landlord or caretaker name', counterText: ''),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _landlordPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Landlord or caretaker phone *'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Anything else we should know'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!,
                style: const TextStyle(color: KhejaColors.red, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ],
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
