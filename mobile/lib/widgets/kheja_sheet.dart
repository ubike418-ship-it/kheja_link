import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Opens [child] as a rounded bottom sheet that rises with the keyboard.
Future<T?> showKhejaSheet<T>(BuildContext context, Widget child) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => child,
  );
}

/// The shared frame for bottom sheets: drag handle, title, a scrolling body
/// that never overflows a small phone, and a primary action pinned below it.
class KhejaSheet extends StatelessWidget {
  const KhejaSheet({
    super.key,
    required this.title,
    required this.children,
    required this.actionLabel,
    required this.onAction,
    this.subtitle,
    this.busy = false,
    this.actionColor,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final Color? actionColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Container(
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
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: KhejaColors.zinc500,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ...children,
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: actionColor,
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(actionLabel),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable field that opens a date picker. Shows [placeholder] when empty.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
    this.placeholder = 'Choose a date',
    this.clearable = false,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;
  final String placeholder;
  final bool clearable;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InkWell(
      borderRadius: BorderRadius.circular(KhejaRadius.md),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: v != null && !v.isBefore(firstDate) && !v.isAfter(lastDate) ? v : firstDate,
          firstDate: firstDate,
          lastDate: lastDate,
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          prefixIcon: const Icon(Icons.event_rounded, size: 20),
          suffixIcon: clearable && v != null
              ? IconButton(
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Clear date',
                )
              : null,
        ),
        child: Text(
          v == null
              ? placeholder
              : MaterialLocalizations.of(context).formatMediumDate(v),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: v == null ? KhejaColors.zinc400 : null,
          ),
        ),
      ),
    );
  }
}
