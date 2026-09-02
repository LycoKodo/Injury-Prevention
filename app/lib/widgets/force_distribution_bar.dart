import 'package:flutter/material.dart';

/// Horizontal stacked bar comparing an estimated force distribution to an ideal one.
/// Labeled "estimated" per protocol (force numbers are estimates from 2D kinematics).
class ForceDistributionBar extends StatelessWidget {
  final Map<String, double> actual;
  final Map<String, double> ideal;

  const ForceDistributionBar({super.key, required this.actual, required this.ideal});

  static const _order = ['legs', 'hips', 'trunk', 'shoulder', 'arm'];
  static const _colors = {
    'legs': Color(0xFF4BA3FF),
    'hips': Color(0xFFB6F000),
    'trunk': Color(0xFFFFC24B),
    'shoulder': Color(0xFF9B6BFF),
    'arm': Color(0xFFFF5D5D),
  };

  @override
  Widget build(BuildContext context) {
    if (actual.isEmpty) {
      return Text('No force distribution data', style: Theme.of(context).textTheme.bodySmall);
    }
    final keys = _order.where((k) => actual.containsKey(k)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Force distribution', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 6),
            Text('(estimated)',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontStyle: FontStyle.italic, color: Colors.white54)),
          ],
        ),
        const SizedBox(height: 6),
        _stackedBar(keys, actual),
        if (ideal.isNotEmpty) ...[
          const SizedBox(height: 4),
          _stackedBar(keys, ideal, dim: true),
          const SizedBox(height: 2),
          Text('top: actual  ·  bottom: ideal',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white38)),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: keys.map((k) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 10, height: 10, color: _colors[k]),
                const SizedBox(width: 4),
                Text('$k ${actual[k]?.toStringAsFixed(0) ?? '--'}%',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _stackedBar(List<String> keys, Map<String, double> data, {bool dim = false}) {
    final total = keys.fold<double>(0, (sum, k) => sum + (data[k] ?? 0));
    final safeTotal = total <= 0 ? 1.0 : total;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 16,
        child: Row(
          children: keys.map((k) {
            final v = data[k] ?? 0;
            final flexValue = ((v / safeTotal) * 1000).round().clamp(0, 1000);
            if (flexValue <= 0) return const SizedBox.shrink();
            return Expanded(
              flex: flexValue,
              child: Container(color: (_colors[k] ?? Colors.grey).withValues(alpha: dim ? 0.35 : 1)),
            );
          }).toList(),
        ),
      ),
    );
  }
}
