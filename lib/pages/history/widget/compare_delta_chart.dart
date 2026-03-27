import 'package:flutter/material.dart';

/// Simple and modern tiny comparison chart: a slope line from [fromValue] to [toValue]
/// with endpoint dots and labels.
class CompareDeltaChart extends StatelessWidget {
  final double fromValue;
  final double toValue;

  const CompareDeltaChart({
    super.key,
    required this.fromValue,
    required this.toValue,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final delta = toValue - fromValue;
    final sign = delta > 0 ? '+' : '';

    final Color lineColor = delta > 0
        ? scheme.primary
        : (delta < 0 ? scheme.error : scheme.outline);

    final background = scheme.surfaceContainerHighest;
    final onBackground = scheme.onSurface;
    final onBackgroundMuted = scheme.onSurfaceVariant;

    // Choose a dot color that always contrasts with the surface.
    // Use onPrimary/onError tones for better contrast with the line glow.
    final Color dotColor = delta > 0
        ? scheme.onPrimary
        : (delta < 0 ? scheme.onError : onBackground);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Trend',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: onBackgroundMuted,
                    ),
              ),
              const Spacer(),
              Text(
                '$sign${delta.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: lineColor,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 64,
            width: double.infinity,
            child: CustomPaint(
              painter: _SlopeLinePainter(
                fromValue: fromValue,
                toValue: toValue,
                lineColor: lineColor,
                dotColor: dotColor,
                gridColor: scheme.outlineVariant,
                labelColor: onBackground,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ValueChip(label: 'From', value: fromValue),
              const SizedBox(width: 8),
              _ValueChip(label: 'To', value: toValue),
            ],
          )
        ],
      ),
    );
  }
}

class _ValueChip extends StatelessWidget {
  final String label;
  final double value;

  const _ValueChip({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        '$label: ${value.toStringAsFixed(2)}',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
            ),
      ),
    );
  }
}

class _SlopeLinePainter extends CustomPainter {
  final double fromValue;
  final double toValue;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final Color labelColor;

  _SlopeLinePainter({
    required this.fromValue,
    required this.toValue,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Padding inside paint area
    const double padX = 10;
    const double padY = 8;

    final rect = Rect.fromLTWH(padX, padY, size.width - padX * 2, size.height - padY * 2);

    // Handle flat case safely
    final minVal = [fromValue, toValue].reduce((a, b) => a < b ? a : b);
    final maxVal = [fromValue, toValue].reduce((a, b) => a > b ? a : b);
    final range = (maxVal - minVal).abs();
    final safeRange = range < 0.000001 ? 1.0 : range;

    double yFor(double v) {
      // Higher values should be higher on screen => smaller y.
      final t = (v - minVal) / safeRange;
      return rect.bottom - (t * rect.height);
    }

    final p0 = Offset(rect.left, yFor(fromValue));
    final p1 = Offset(rect.right, yFor(toValue));

    // Subtle grid line
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), gridPaint);

    // Slope line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p0, p1, linePaint);

    // Endpoint dots
    final dotPaint = Paint()..color = dotColor;
    final rOuter = 5.0;
    final rInner = 2.5;

    canvas.drawCircle(p0, rOuter, Paint()..color = lineColor.withValues(alpha: 0.22));
    canvas.drawCircle(p1, rOuter, Paint()..color = lineColor.withValues(alpha: 0.22));
    canvas.drawCircle(p0, rInner, dotPaint);
    canvas.drawCircle(p1, rInner, dotPaint);

    // Value labels near endpoints (small + readable)
    final tp0 = TextPainter(
      text: TextSpan(
        text: fromValue.toStringAsFixed(0),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final tp1 = TextPainter(
      text: TextSpan(
        text: toValue.toStringAsFixed(0),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // Use a small pill background with labelColor-driven text.
    void drawLabel(TextPainter tp, Offset anchor, bool left) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left ? anchor.dx : anchor.dx - tp.width,
          anchor.dy - tp.height - 6,
          tp.width,
          tp.height,
        ).inflate(6),
        const Radius.circular(10),
      );
      canvas.drawRRect(r, Paint()..color = lineColor.withValues(alpha: 0.08));

      // repaint text with desired color
      final colored = TextPainter(
        text: TextSpan(
          text: (tp.text as TextSpan?)?.text ?? '',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      colored.paint(
        canvas,
        Offset(
          left ? anchor.dx + 2 : anchor.dx - colored.width - 2,
          anchor.dy - colored.height - 6,
        ),
      );
    }

    // Draw labels; keep them inside rect as best-effort.
    drawLabel(tp0, p0.translate(0, 0), true);
    drawLabel(tp1, p1.translate(0, 0), false);
  }

  @override
  bool shouldRepaint(covariant _SlopeLinePainter oldDelegate) {
    return oldDelegate.fromValue != fromValue ||
        oldDelegate.toValue != toValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.dotColor != dotColor ||
        oldDelegate.gridColor != gridColor;
  }
}
