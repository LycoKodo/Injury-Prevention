import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Compact horizontal gauge: label + value on the left, a small bar with an
/// optional target band on the right. Value may be null (renders "--").
class MetricGauge extends StatelessWidget {
  final String label;
  final double? value;
  final String unit;
  final double min;
  final double max;
  final double? targetMin;
  final double? targetMax;

  const MetricGauge({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    required this.min,
    required this.max,
    this.targetMin,
    this.targetMax,
  });

  double _fraction(double v) => ((v - min) / (max - min)).clamp(0.0, 1.0);

  bool get _inTarget {
    if (value == null || targetMin == null || targetMax == null) return true;
    return value! >= targetMin! && value! <= targetMax!;
  }

  @override
  Widget build(BuildContext context) {
    final fraction = value == null ? null : _fraction(value!);
    final color = value == null
        ? Colors.grey
        : (_inTarget ? AppTheme.good : AppTheme.warn);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                return SizedBox(
                  height: 14,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      if (targetMin != null && targetMax != null)
                        Positioned(
                          left: w * _fraction(targetMin!),
                          width: (w * (_fraction(targetMax!) - _fraction(targetMin!))).abs(),
                          top: 0,
                          bottom: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      if (fraction != null)
                        FractionallySizedBox(
                          widthFactor: fraction.clamp(0.02, 1.0),
                          alignment: Alignment.centerLeft,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              value == null ? '--' : '${value!.toStringAsFixed(1)}$unit',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
