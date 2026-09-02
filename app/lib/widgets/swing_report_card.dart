import 'package:flutter/material.dart';

import '../models/feedback.dart' as fb;
import '../models/kinetic_chain.dart';
import '../models/swing_report.dart';
import '../theme/app_theme.dart';
import 'force_distribution_bar.dart';
import 'score_ring.dart';

/// Full swing report: efficiency/injury-risk rings, force distribution bar,
/// kinetic-chain sequencing indicator, and the feedback list.
class SwingReportCard extends StatelessWidget {
  final SwingReport report;

  const SwingReportCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final chain = report.kineticChain;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  report.id != null ? 'Swing #${report.id}' : 'Swing',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                if (report.tContact != null)
                  Text('contact @ ${report.tContact!.toStringAsFixed(2)}s',
                      style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ScoreRing(value: report.efficiencyScore, label: 'Efficiency'),
                ScoreRing(value: report.injuryRiskScore, label: 'Injury Risk', higherIsWorse: true),
              ],
            ),
            const SizedBox(height: 16),
            ForceDistributionBar(
              actual: report.forceDistribution,
              ideal: report.idealDistribution,
            ),
            const SizedBox(height: 16),
            _KineticChainRow(chain: chain),
            const SizedBox(height: 16),
            if (report.feedback.isNotEmpty) ...[
              Text('Feedback', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              ...report.feedback.map((f) => _FeedbackTile(feedback: f)),
            ],
          ],
        ),
      ),
    );
  }
}

class _KineticChainRow extends StatelessWidget {
  final KineticChain chain;
  const _KineticChainRow({required this.chain});

  @override
  Widget build(BuildContext context) {
    final ok = chain.sequencingOk;
    final lagHipShoulder = chain.lagHipToShoulderMs;
    final lagShoulderArm = chain.lagShoulderToArmMs;
    return Row(
      children: [
        Icon(
          ok == null ? Icons.help_outline : (ok ? Icons.check_circle : Icons.warning_amber_rounded),
          color: ok == null ? Colors.grey : (ok ? AppTheme.good : AppTheme.warn),
          size: 18,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Hip → Shoulder → Arm'
            '${lagHipShoulder != null ? '  (${lagHipShoulder.toStringAsFixed(0)}ms' : ''}'
            '${lagShoulderArm != null ? ' / ${lagShoulderArm.toStringAsFixed(0)}ms)' : (lagHipShoulder != null ? ')' : '')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  final fb.Feedback feedback;
  const _FeedbackTile({required this.feedback});

  IconData get _icon {
    switch (feedback.severity) {
      case fb.FeedbackSeverity.good:
        return Icons.check_circle_outline;
      case fb.FeedbackSeverity.warn:
        return Icons.warning_amber_rounded;
      case fb.FeedbackSeverity.danger:
        return Icons.error_outline;
      case fb.FeedbackSeverity.unknown:
        return Icons.info_outline;
    }
  }

  Color get _color {
    switch (feedback.severity) {
      case fb.FeedbackSeverity.good:
        return AppTheme.good;
      case fb.FeedbackSeverity.warn:
        return AppTheme.warn;
      case fb.FeedbackSeverity.danger:
        return AppTheme.danger;
      case fb.FeedbackSeverity.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, color: _color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feedback.title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (feedback.detail.isNotEmpty)
                  Text(feedback.detail, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
