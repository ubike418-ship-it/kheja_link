import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/models.dart';

/// The filter sheet — house type, area, bedrooms, budget, amenities and the
/// two boolean toggles, matching the web app's filter panel field for field.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.filters,
    required this.types,
    required this.locations,
    required this.amenities,
    this.bounds,
  });

  final PropertyFilters filters;
  final List<PropertyType> types;
  final List<KhejaLocation> locations;
  final List<Amenity> amenities;
  final ({num min, num max})? bounds;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late PropertyFilters _draft;
  late double _maxPrice;

  num get _floor => widget.bounds?.min ?? 0;
  num get _ceiling => widget.bounds?.max ?? 100000;

  @override
  void initState() {
    super.initState();
    _draft = widget.filters;
    _maxPrice = (_draft.maxPrice ?? _ceiling).toDouble();
  }

  void _apply() {
    // A max at the very top of the range is the same as "no limit".
    final atCeiling = _maxPrice >= _ceiling.toDouble();
    Navigator.of(context)
        .pop(_draft.copyWith(maxPrice: atCeiling ? null : _maxPrice.round()));
  }

  void _reset() {
    setState(() {
      _draft = PropertyFilters(query: widget.filters.query);
      _maxPrice = _ceiling.toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(KhejaRadius.xxl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: KhejaColors.zinc300,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 8),
            child: Row(
              children: [
                Text('Filters', style: theme.textTheme.headlineSmall),
                const Spacer(),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              children: [
                _Label('House type'),
                _ChoiceWrap<String?>(
                  value: _draft.typeSlug,
                  options: [
                    (value: null, label: 'Any type'),
                    ...widget.types.map((t) => (value: t.slug, label: t.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(typeSlug: value)),
                ),
                const SizedBox(height: 26),

                _Label('Area'),
                _ChoiceWrap<String?>(
                  value: _draft.locationSlug,
                  options: [
                    (value: null, label: 'Anywhere'),
                    ...widget.locations.map((l) => (value: l.slug, label: l.name)),
                  ],
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(locationSlug: value)),
                ),
                const SizedBox(height: 26),

                _Label('Bedrooms'),
                _ChoiceWrap<int?>(
                  value: _draft.bedrooms,
                  options: const [
                    (value: null, label: 'Any'),
                    (value: 1, label: '1+'),
                    (value: 2, label: '2+'),
                    (value: 3, label: '3+'),
                    (value: 4, label: '4+'),
                  ],
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(bedrooms: value)),
                ),
                const SizedBox(height: 26),

                _Label(
                  _maxPrice >= _ceiling.toDouble()
                      ? 'Max rent — any'
                      : 'Max rent — ${formatPrice(_maxPrice.round())}',
                ),
                Slider(
                  value: _maxPrice.clamp(_floor.toDouble(), _ceiling.toDouble()),
                  min: _floor.toDouble(),
                  max: _ceiling.toDouble(),
                  divisions: (((_ceiling - _floor) / 1000).round()).clamp(1, 200),
                  activeColor: KhejaColors.blue,
                  label: formatPrice(_maxPrice.round()),
                  onChanged: (value) => setState(() => _maxPrice = value),
                ),
                const SizedBox(height: 18),

                if (widget.amenities.isNotEmpty) ...[
                  _Label('Must have'),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: widget.amenities.map((amenity) {
                      final selected = _draft.amenitySlugs.contains(amenity.slug);
                      return _Pill(
                        label: amenity.name,
                        selected: selected,
                        icon: selected ? Icons.check_rounded : null,
                        onTap: () {
                          final next = [..._draft.amenitySlugs];
                          if (selected) {
                            next.remove(amenity.slug);
                          } else {
                            next.add(amenity.slug);
                          }
                          setState(
                              () => _draft = _draft.copyWith(amenitySlugs: next));
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 26),
                ],

                _Label('Sort by'),
                _ChoiceWrap<PropertySort>(
                  value: _draft.sort,
                  options: PropertySort.values
                      .map((s) => (value: s, label: s.label))
                      .toList(),
                  onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(sort: value ?? PropertySort.newest)),
                ),
                const SizedBox(height: 26),

                _SwitchRow(
                  label: 'Furnished only',
                  value: _draft.furnished,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(furnished: value)),
                ),
                _SwitchRow(
                  label: 'Premium units only',
                  value: _draft.premium,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(premium: value)),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: FilledButton(
                onPressed: _apply,
                child: const Text('Show homes'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400),
      ),
    );
  }
}

class _ChoiceWrap<T> extends StatelessWidget {
  const _ChoiceWrap({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<({T value, String label})> options;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((option) {
        return _Pill(
          label: option.label,
          selected: option.value == value,
          onTap: () => onChanged(option.value),
        );
      }).toList(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? KhejaColors.blue : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(KhejaRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KhejaRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KhejaRadius.md),
            border: Border.all(
              color: selected ? KhejaColors.blue : theme.colorScheme.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: Colors.white),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: selected ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeThumbColor: KhejaColors.blue,
      contentPadding: EdgeInsets.zero,
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    );
  }
}
