import 'package:flutter/material.dart';

import '../config/theme.dart';

/// One step of a guided tour.
///
/// [target] is the real widget on screen to spotlight. When it is null, or not
/// built at the moment (an empty list, say), the step shows as a centred card
/// instead, so a tour never breaks because a screen has no data yet.
class CoachStep {
  const CoachStep({
    required this.title,
    required this.body,
    required this.icon,
    this.target,
    this.color = KhejaColors.blue,
    this.chips = const [],
  });

  final GlobalKey? target;
  final String title;
  final String body;
  final IconData icon;
  final Color color;

  /// Short labels shown under the text, e.g. the property categories.
  final List<String> chips;
}

enum CoachResult { finished, skipped }

/// Runs a tour over the current screen and resolves when it ends.
///
/// The tour sits on the root navigator, above the tab bar, and blocks taps on
/// the UI underneath so nobody navigates away mid-step by accident.
Future<CoachResult> showCoachMarks(
  BuildContext context, {
  required List<CoachStep> steps,
  required String eyebrow,
}) async {
  if (steps.isEmpty) return CoachResult.finished;
  final result = await Navigator.of(context, rootNavigator: true).push<CoachResult>(
    PageRouteBuilder<CoachResult>(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => _CoachOverlay(steps: steps, eyebrow: eyebrow),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
  return result ?? CoachResult.skipped;
}

class _CoachOverlay extends StatefulWidget {
  const _CoachOverlay({required this.steps, required this.eyebrow});

  final List<CoachStep> steps;
  final String eyebrow;

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> {
  int _index = 0;

  /// The spotlight, in global coordinates. Null means "no target: centre it".
  Rect? _hole;
  bool _measuring = true;

  CoachStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus());
  }

  Future<void> _focus() async {
    setState(() => _measuring = true);
    final targetContext = _step.target?.currentContext;

    if (targetContext != null && targetContext.mounted) {
      try {
        // Bring it into view first; a tour pointing at something off-screen
        // is worse than no tour.
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.3,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      } catch (_) {
        // Not inside a scrollable — it is already where it will be.
      }
    }

    // Let the scroll settle before measuring.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;

    Rect? hole;
    final box = _step.target?.currentContext?.findRenderObject();
    if (box is RenderBox && box.attached && box.hasSize) {
      final origin = box.localToGlobal(Offset.zero);
      final screen = Offset.zero & MediaQuery.of(context).size;
      final rect = (origin & box.size).inflate(8).intersect(screen);
      // Too small or entirely off-screen: fall back to a centred card.
      if (rect.width > 24 && rect.height > 24) hole = rect;
    }

    setState(() {
      _hole = hole;
      _measuring = false;
    });
  }

  void _go(int delta) {
    final next = _index + delta;
    if (next < 0) return;
    if (next >= widget.steps.length) {
      Navigator.of(context).pop(CoachResult.finished);
      return;
    }
    setState(() => _index = next);
    _focus();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final hole = _hole;

    return PopScope(
      canPop: false,
      // Android back steps backwards, and leaves the tour from the first step.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index == 0) {
          Navigator.of(context).pop(CoachResult.skipped);
        } else {
          _go(-1);
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // The dimmed backdrop with its cut-out. Absorbs every tap.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(
                    end: hole ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0),
                  ),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (_, rect, __) => CustomPaint(
                    painter: _SpotlightPainter(hole: rect, ringColor: _step.color),
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(CoachResult.skipped),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Skip tour'),
                  ),
                ),
              ),
            ),

            if (!_measuring) _placeCard(context, size, media.padding, hole),
          ],
        ),
      ),
    );
  }

  /// Puts the card on whichever side of the spotlight has more room, and lets
  /// it scroll rather than overflow on a small phone.
  Widget _placeCard(BuildContext context, Size size, EdgeInsets padding, Rect? hole) {
    final width = (size.width - 32).clamp(0.0, 440.0);
    final left = (size.width - width) / 2;

    if (hole == null) {
      return Positioned(
        left: left,
        width: width,
        top: padding.top + 64,
        bottom: padding.bottom + 24,
        child: Center(child: _card(context, maxHeight: size.height * 0.7)),
      );
    }

    final spaceAbove = hole.top - padding.top - 64;
    final spaceBelow = size.height - hole.bottom - padding.bottom - 16;

    if (spaceBelow >= spaceAbove) {
      return Positioned(
        left: left,
        width: width,
        top: hole.bottom + 14,
        child: _card(context, maxHeight: spaceBelow - 14),
      );
    }
    return Positioned(
      left: left,
      width: width,
      bottom: size.height - hole.top + 14,
      child: _card(context, maxHeight: spaceAbove - 14),
    );
  }

  Widget _card(BuildContext context, {required double maxHeight}) {
    final theme = Theme.of(context);
    final step = _step;
    final total = widget.steps.length;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight.clamp(180.0, double.infinity)),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(KhejaRadius.xl),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: step.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(KhejaRadius.md),
                      ),
                      child: Icon(step.icon, size: 21, color: step.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${widget.eyebrow} · STEP ${_index + 1} OF $total',
                        style: kEyebrowStyle.copyWith(color: step.color),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(step.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  step.body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: KhejaColors.zinc500,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
                if (step.chips.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final chip in step.chips)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: step.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: step.color.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            chip,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (var i = 0; i < total; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 5),
                        width: i == _index ? 18 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _index ? step.color : KhejaColors.zinc300,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    const Spacer(),
                    if (_index > 0)
                      TextButton(onPressed: () => _go(-1), child: const Text('Previous')),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => _go(1),
                      style: FilledButton.styleFrom(
                        backgroundColor: step.color,
                        minimumSize: const Size(96, 46),
                      ),
                      child: Text(_isLast ? 'Finish' : 'Next'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.ringColor});

  final Rect? hole;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);

    final h = hole;
    final hasHole = h != null && h.width > 1 && h.height > 1;
    RRect? rrect;
    if (hasHole) {
      rrect = RRect.fromRectAndRadius(h, const Radius.circular(KhejaRadius.lg));
      path.addRRect(rrect);
    }

    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.72));

    if (rrect != null) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = ringColor,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole || old.ringColor != ringColor;
}
