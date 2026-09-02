import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact circular score indicator for a 0..100 value (or "--" when null).
class ScoreRing extends StatelessWidget {
  final int? value;
  final String label;
  final bool higherIsWorse;
  final double size;

  const ScoreRing({
    super.key,
    required this.value,
    required this.label,
    this.higherIsWorse = false,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.scoreColor(value, higherIsWorse: higherIsWorse);
    final fraction = value == null ? 0.0 : (value!.clamp(0, 100)) / 100.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: 8,
                  backgroundColor: Colors.white.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Text(
                value?.toString() ?? '--',
                style: TextStyle(
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
