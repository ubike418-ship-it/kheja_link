import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The Kheja_Link mark.
///
/// The supplied logo is a photograph on a dark ground, so it is always set in a
/// rounded tile — that keeps it looking deliberate on both the light and dark
/// themes instead of floating as a dark square.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 40, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.28),
      child: Image.asset(
        'assets/branding/logo.jpeg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// The full brand lockup artwork (mark + wordmark), for the places with room
/// to show it properly: the splash and the auth screens. The launcher icon and
/// navbar use [LogoMark] instead, since a wordmark is illegible at icon sizes.
class LogoLockup extends StatelessWidget {
  const LogoLockup({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(KhejaRadius.lg),
      child: Image.asset(
        'assets/branding/lockup.jpeg',
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

/// Mark plus wordmark, as it appears in the web navbar.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.size = 36, this.fontSize = 22});

  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LogoMark(size: size),
        const SizedBox(width: 10),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: onSurface,
            ),
            children: const [
              TextSpan(text: 'KHEJA'),
              TextSpan(text: '_LINK', style: TextStyle(color: KhejaColors.blue)),
            ],
          ),
        ),
      ],
    );
  }
}

/// The all-caps eyebrow label above section headings.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.icon, this.color = KhejaColors.blue});

  final String text;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Text(text.toUpperCase(), style: kEyebrowStyle.copyWith(color: color)),
      ],
    );
  }
}

/// Status chip for a listing, matching the web dashboard.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'published' => (KhejaColors.emerald.withValues(alpha: 0.12), KhejaColors.emerald),
      'draft' => (KhejaColors.amber.withValues(alpha: 0.12), KhejaColors.amber),
      'rented' => (KhejaColors.blue.withValues(alpha: 0.12), KhejaColors.blue),
      _ => (KhejaColors.zinc400.withValues(alpha: 0.16), KhejaColors.zinc500),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KhejaRadius.sm),
      ),
      child: Text(
        status.toUpperCase(),
        style: kEyebrowStyle.copyWith(color: fg, letterSpacing: 1.4),
      ),
    );
  }
}
