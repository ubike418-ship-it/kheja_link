import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/theme.dart';

/// The Kheja_Link mark.
///
/// The supplied logo is a hard-edged photograph on a dark ground. Dropped in
/// raw it reads as a screenshot, so it is treated: a blurred copy of itself
/// glows behind the tile, the image is very slightly softened, and a diagonal
/// sheen runs across it. The result sits in the UI as a designed mark rather
/// than a pasted picture.
class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    this.size = 40,
    this.radius,
    this.blurred = true,
  });

  final double size;
  final double? radius;

  /// Set false for the few places that need the raw asset.
  final bool blurred;

  @override
  Widget build(BuildContext context) {
    final corner = radius ?? size * 0.29;
    // Enough to take the hard pixel edges off without turning it to mush.
    final softness = (size * 0.006).clamp(0.15, 0.9);

    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(corner),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (blurred)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: softness, sigmaY: softness),
              child: _image(size),
            )
          else
            _image(size),

          // A soft diagonal sheen, so the tile catches light like a real object.
          if (blurred)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.16),
                    Colors.white.withValues(alpha: 0.02),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
        ],
      ),
    );

    if (!blurred) {
      return SizedBox(width: size, height: size, child: tile);
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The glow: a heavily blurred, scaled copy sitting behind the tile.
          Positioned(
            left: -size * 0.08,
            top: size * 0.02,
            right: -size * 0.08,
            bottom: -size * 0.06,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.55,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: size * 0.16,
                    sigmaY: size * 0.16,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(corner),
                    child: _image(size),
                  ),
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(corner),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: size * 0.28,
                  offset: Offset(0, size * 0.08),
                ),
              ],
            ),
            child: tile,
          ),
        ],
      ),
    );
  }

  Widget _image(double size) => Image.asset(
        'assets/branding/logo.jpeg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
}

/// The full brand lockup artwork (mark + wordmark), for the places with room
/// to show it properly: the splash and the auth screens. The launcher icon and
/// navbar use [LogoMark] instead, since a wordmark is illegible at icon sizes.
class LogoLockup extends StatelessWidget {
  const LogoLockup({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Same treatment as the mark: a soft bloom so it does not read flat.
        IgnorePointer(
          child: Opacity(
            opacity: 0.5,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(KhejaRadius.lg),
                child: Image.asset(
                  'assets/branding/lockup.jpeg',
                  width: width * 0.92,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 0.3, sigmaY: 0.3),
            child: Image.asset(
              'assets/branding/lockup.jpeg',
              width: width,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
            ),
          ),
        ),
      ],
    );
  }
}

/// Mark plus wordmark, as it appears in the app bar.
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
