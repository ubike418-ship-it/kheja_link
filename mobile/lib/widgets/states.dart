import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../config/theme.dart';
import '../services/network.dart';

/// Loading, empty and error states — every screen that touches the network
/// uses these, so the app never shows a bare spinner or a raw exception.

class PropertyCardSkeleton extends StatelessWidget {
  const PropertyCardSkeleton({super.key, this.imageHeight = 230});

  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? KhejaColors.zinc800 : KhejaColors.zinc200;
    final highlight = isDark ? KhejaColors.zinc600 : KhejaColors.zinc100;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(KhejaRadius.xxl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: imageHeight,
              decoration: BoxDecoration(
                color: base,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(KhejaRadius.xxl),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(width: 220, height: 22, color: base),
                  const SizedBox(height: 10),
                  _Bar(width: 140, height: 14, color: base),
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(
                      3,
                      (_) => _Bar(width: 56, height: 30, color: base),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class KhejaEmptyState extends StatelessWidget {
  const KhejaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: 0.2,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: isDark ? KhejaColors.zinc900 : KhejaColors.zinc100,
                  borderRadius: BorderRadius.circular(KhejaRadius.xl),
                ),
                child: Icon(icon, size: 44, color: KhejaColors.zinc300),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: 240,
                child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class KhejaErrorState extends StatelessWidget {
  const KhejaErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // "You are offline" and "the server said no" need different words. On a
    // patchy mobile connection the first is by far the more common.
    final offline = KhejaNetwork.isConnectionError(message);

    return KhejaEmptyState(
      icon: offline ? Icons.signal_wifi_off_rounded : Icons.error_outline_rounded,
      title: offline ? 'No connection' : 'Could not load',
      message: offline
          ? 'We could not reach Kheja_Link. Check your mobile data or WiFi and '
              'try again — your saved homes are safe.'
          : message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

/// A section heading with its eyebrow, used at the top of most screens.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    this.icon,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final IconData? icon;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: KhejaColors.blue),
              const SizedBox(width: 6),
            ],
            Text(
              eyebrow.toUpperCase(),
              style: kEyebrowStyle.copyWith(color: KhejaColors.blue),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(title, style: theme.textTheme.displaySmall),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(
            subtitle!,
            style: theme.textTheme.bodyLarge?.copyWith(color: KhejaColors.zinc500),
          ),
        ],
      ],
    );
  }
}

void showKhejaSnack(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? KhejaColors.red : null,
      ),
    );
}
