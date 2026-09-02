import 'package:flutter/material.dart';

import '../models/coach_message.dart';
import '../services/backend_client.dart';
import '../theme/app_theme.dart';

/// Headline "talking coach" card: shows the latest problem/fix cues, a live
/// "Speaking…" indicator while the backend plays audio through the Mac
/// speakers, a low-key provenance footnote, and skipped-swing notices.
///
/// This widget only displays — it never plays audio itself, the backend does.
class CoachCard extends StatefulWidget {
  final CoachState state;

  const CoachCard({super.key, required this.state});

  @override
  State<CoachCard> createState() => _CoachCardState();
}

class _CoachCardState extends State<CoachCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.state.speaking) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant CoachCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.speaking && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.state.speaking && _pulseController.isAnimating) {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final message = state.message;
    final hasContent = message != null && message.items.isNotEmpty;

    return Card(
      color: AppTheme.surfaceCardAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.courtGreen.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context, state),
            const SizedBox(height: 10),
            if (!hasContent) _buildIdle(context) else _buildItems(context, message.items),
            if (hasContent) ...[
              const SizedBox(height: 10),
              _buildProvenance(context, message),
            ],
            if (state.skippedSwingId != null) ...[
              const SizedBox(height: 8),
              _buildSkipped(context, state.skippedSwingId!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CoachState state) {
    return Row(
      children: [
        Icon(
          state.speaking ? Icons.record_voice_over : Icons.mic_none,
          size: 18,
          color: state.speaking ? AppTheme.courtGreen : Colors.white54,
        ),
        const SizedBox(width: 8),
        Text('Coach', style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        if (state.speaking) _SpeakingIndicator(controller: _pulseController),
      ],
    );
  }

  Widget _buildIdle(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.mic_off_outlined, size: 16, color: Colors.white38),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Coach is listening',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white38),
          ),
        ),
      ],
    );
  }

  Widget _buildItems(BuildContext context, List<CoachItem> allItems) {
    final items = allItems.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _CoachItemTile(item: items[i]),
        ],
      ],
    );
  }

  Widget _buildProvenance(BuildContext context, CoachMessage message) {
    final parts = <String>[];
    parts.add(message.source == 'local' ? 'offline coach' : (message.source ?? 'coach'));
    if (message.generateMs != null) parts.add('${message.generateMs}ms');
    return Text(
      parts.join(' · '),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white30),
    );
  }

  Widget _buildSkipped(BuildContext context, int swingId) {
    return Row(
      children: [
        const Icon(Icons.fast_forward_outlined, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Skipped swing #$swingId — still coaching the last one',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white38),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _CoachItemTile extends StatelessWidget {
  final CoachItem item;
  const _CoachItemTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final problem = item.problem;
    final fix = item.fix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (problem != null && problem.isNotEmpty)
          _CueLine(
            icon: Icons.warning_amber_rounded,
            color: AppTheme.warn,
            label: 'Problem',
            text: problem,
            emphasize: false,
          ),
        if (fix != null && fix.isNotEmpty) ...[
          const SizedBox(height: 4),
          _CueLine(
            icon: Icons.check_circle_outline,
            color: AppTheme.courtGreen,
            label: 'Fix',
            text: fix,
            emphasize: true,
          ),
        ],
      ],
    );
  }
}

/// One "Problem" or "Fix" line. The fix line is rendered visually stronger
/// (bold, brighter text, filled icon) since it is the actionable half.
class _CueLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String text;
  final bool emphasize;

  const _CueLine({
    required this.icon,
    required this.color,
    required this.label,
    required this.text,
    required this.emphasize,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: emphasize ? Colors.white : Colors.white.withValues(alpha: 0.78),
          fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: emphasize ? 18 : 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
              ),
              Text(text, style: textStyle),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small animated "speaking" indicator: three bars pulsing out of phase,
/// plus the label "Speaking…".
class _SpeakingIndicator extends StatelessWidget {
  final AnimationController controller;
  const _SpeakingIndicator({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 14,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(3, (i) {
                  final phase = (controller.value + i * 0.33) % 1.0;
                  final height = 4 + 10 * (0.5 - (phase - 0.5).abs()) * 2;
                  return Container(
                    width: 4,
                    height: height.clamp(4.0, 14.0),
                    decoration: BoxDecoration(
                      color: AppTheme.courtGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Speaking…',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppTheme.courtGreen),
        ),
      ],
    );
  }
}
