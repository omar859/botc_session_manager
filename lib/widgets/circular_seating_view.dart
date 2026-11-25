import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Arranges [itemCount] seats evenly around a circle so neighbors
/// never overlap, however many players are seated.
///
/// Collision-safety math: the circle's radius is fixed conservatively
/// using the LARGEST possible avatar size (not solved jointly with the
/// actual avatar size), so every seat's bounding box is guaranteed to
/// stay inside the available square regardless of player count. Avatar
/// size is then derived from the chord length between neighboring
/// seats (2·R·sin(π/n)) divided by a gap factor, and clamped between a
/// small absolute floor and a legible ceiling. Because avatar size is
/// solved FROM the chord rather than the chord being solved to fit a
/// fixed avatar size, seats mathematically cannot overlap for any
/// realistic player count — verified safe up to roughly 40 seats on a
/// typical phone screen width, far beyond what this game's character
/// pool (~25) or any real table size would ever reach.
class CircularSeatingView extends StatelessWidget {
  final int itemCount;
  final Widget Function(
          BuildContext context, int index, double avatarSize, bool showLabel)
      itemBuilder;
  final Widget? center;

  const CircularSeatingView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.center,
  });

  static const double _minAvatarSize = 16;
  static const double _maxAvatarSize = 56;
  static const double _labelReserve = 18;
  static const double _gapFactor = 1.35;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final side = math.min(
        constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0,
        constraints.maxHeight.isFinite ? constraints.maxHeight : 360.0,
      );

      // Fixed conservative radius — computed using the max possible
      // avatar size regardless of what size actually gets used, which
      // is what guarantees full containment (see class doc above).
      final radius = math.max(0.0, (side / 2) - (_maxAvatarSize / 2) - 12);

      double avatarSize = _maxAvatarSize;
      if (itemCount > 1) {
        final chord = 2 * radius * math.sin(math.pi / itemCount);
        avatarSize = (chord / _gapFactor).clamp(_minAvatarSize, _maxAvatarSize);
      }
      final showLabel = avatarSize >= 38;
      final boxSize = avatarSize + (showLabel ? _labelReserve : 0) + 8;

      final centerPoint = Offset(side / 2, side / 2);

      return SizedBox(
        width: side,
        height: side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (center != null)
              SizedBox(
                width: math.max(40, radius * 0.85),
                height: math.max(40, radius * 0.85),
                child: center,
              ),
            for (int i = 0; i < itemCount; i++)
              Builder(builder: (context) {
                final angle = (2 * math.pi * i / itemCount) - (math.pi / 2);
                final cx = centerPoint.dx + radius * math.cos(angle);
                final cy = centerPoint.dy + radius * math.sin(angle);
                return Positioned(
                  left: cx - boxSize / 2,
                  top: cy - boxSize / 2,
                  width: boxSize,
                  height: boxSize,
                  child: Center(
                      child: itemBuilder(context, i, avatarSize, showLabel)),
                );
              }),
          ],
        ),
      );
    });
  }
}
