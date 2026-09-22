import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/kheja_sheet.dart';
import '../widgets/states.dart';

/// "Notify me when a home like this becomes available."
///
/// Saves a standing search. Whenever a matching home becomes available — or
/// gets a vacancy date within the chosen window — the database notifies the
/// tenant in their Inbox.
class SearchAlertSheet extends StatefulWidget {
  const SearchAlertSheet({super.key, this.initial = const PropertyFilters()});

  /// Pre-fills from the search the tenant is looking at.
  final PropertyFilters initial;

  @override
  State<SearchAlertSheet> createState() => _SearchAlertSheetState();
}

class _SearchAlertSheetState extends State<SearchAlertSheet> {
  List<PropertyType> _types = const [];
  List<KhejaLocation> _locations = const [];
  bool _loadingLists = true;
  String? _listError;

  String? _typeId;
  String? _locationId;
  int? _bedrooms;
  int? _withinDays;
  final _min = TextEditingController();
  final _max = TextEditingController();
  bool _saving = false;
  String? _budgetError;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    _bedrooms = f.bedrooms;
    if (f.minPrice != null) _min.text = f.minPrice!.round().toString();
    if (f.maxPrice != null) _max.text = f.maxPrice!.round().toString();
    _loadLists();
  }

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
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
      final types = results[0] as List<PropertyType>;
      final locations = results[1] as List<KhejaLocation>;
      setState(() {
        _types = types;
        _locations = locations;
        _typeId = types.where((t) => t.slug == widget.initial.typeSlug).firstOrNull?.id;
        _locationId =
            locations.where((l) => l.slug == widget.initial.locationSlug).firstOrNull?.id;
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

  Future<void> _save() async {
    final min = num.tryParse(_min.text.trim());
    final max = num.tryParse(_max.text.trim());
    if (min != null && max != null && min > max) {
      setState(() => _budgetError = 'The lowest rent is above the highest');
      return;
    }
    if (_typeId == null && _locationId == null && _bedrooms == null && min == null && max == null) {
      setState(() => _budgetError = 'Choose at least one thing to match on');
      return;
    }

    setState(() {
      _saving = true;
      _budgetError = null;
    });
    try {
      await khejaApi.createSearchAlert(
        propertyTypeId: _typeId,
        locationId: _locationId,
        minPrice: min,
        maxPrice: max,
        bedrooms: _bedrooms,
        availableWithinDays: _withinDays,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  Widget _chips<T>({
    required String label,
    required List<(T?, String)> options,
    required T? value,
    required ValueChanged<T?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (v, text) in options)
              ChoiceChip(
                label: Text(text),
                selected: value == v,
                onSelected: (_) => onChanged(v),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return KhejaSheet(
      title: 'Get notified about new homes',
      subtitle: 'Tell us what you are looking for. We will let you know when a matching '
          'home becomes available.',
      actionLabel: 'Save alert',
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
          DropdownButtonFormField<String?>(
            initialValue: _typeId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Property type'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Any type')),
              for (final t in _types) DropdownMenuItem(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => _typeId = v),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String?>(
            initialValue: _locationId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Preferred area'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Anywhere in Meru')),
              for (final l in _locations) DropdownMenuItem(value: l.id, child: Text(l.name)),
            ],
            onChanged: (v) => setState(() => _locationId = v),
          ),
          const SizedBox(height: 18),
          _chips<int>(
            label: 'Bedrooms',
            value: _bedrooms,
            onChanged: (v) => setState(() => _bedrooms = v),
            options: const [(null, 'Any'), (1, '1'), (2, '2'), (3, '3'), (4, '4')],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Min rent (KSh)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Max rent (KSh)'),
                ),
              ),
            ],
          ),
          if (_budgetError != null) ...[
            const SizedBox(height: 8),
            Text(_budgetError!,
                style: const TextStyle(color: KhejaColors.red, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ],
          const SizedBox(height: 18),
          _chips<int>(
            label: 'Available within',
            value: _withinDays,
            onChanged: (v) => setState(() => _withinDays = v),
            options: const [(null, 'Any time'), (7, '7 days'), (30, '30 days'), (60, '60 days')],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
