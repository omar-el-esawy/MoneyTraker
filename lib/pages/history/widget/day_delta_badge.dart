import 'package:flutter/material.dart';
import 'package:money_traker/pages/widgets/obscurable_amount.dart';

class DayDeltaBadge extends StatelessWidget {
  final double delta;
  final bool showAmount;

  const DayDeltaBadge({
    super.key,
    required this.delta,
    this.showAmount = true,
  });

  @override
  Widget build(BuildContext context) {
    final sign = delta > 0 ? '+' : (delta < 0 ? '-' : '');
    final abs = delta.abs().toStringAsFixed(2);
    final color =
        !showAmount
            ? const Color(0xFF6B7280)
            : (delta > 0
                ? const Color(0xFF16A34A)
                : (delta < 0
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF6B7280)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: ObscurableAmount(
        amount: '$sign$abs',
        visible: showAmount,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

