import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/analysis_result.dart';
import '../models/swing_report.dart';
import '../models/trajectory_point.dart';
import '../services/app_settings.dart';
import '../services/backend_client.dart';
import '../theme/app_theme.dart';
import '../widgets/swing_report_card.dart';

class AnalyzeScreen extends StatefulWidget {
  final AppSettings settings;

  const AnalyzeScreen({super.key, required this.settings});

  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  String _handedness = 'auto';
  String _model = 'lite';
  bool _busy = false;
  double _progress = 0;
  String? _error;
  AnalysisResult? _result;
  int? _expandedSwingId;
  int? _selectedTrajectorySwingIndex;

  Future<void> _pickAndAnalyze() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'm4v'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) {
      setState(() => _error = 'Could not read the selected file path.');
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
      _result = null;
    });

    final client = BackendClient(baseUrl: widget.settings.backendUrl);
    try {
      final result = await client.analyzeVideo(
        path,
        handedness: _handedness,
        model: _model,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        setState(() {
          _result = result;
          _selectedTrajectorySwingIndex = result.swings.isNotEmpty ? 0 : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Analysis failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Analyze Video', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'lite', label: Text('Lite')),
                  ButtonSegment(value: 'heavy', label: Text('Heavy')),
                ],
                selected: {_model},
                onSelectionChanged: _busy ? null : (s) => setState(() => _model = s.first),
              ),
              const SizedBox(width: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'auto', label: Text('Auto')),
                  ButtonSegment(value: 'left', label: Text('Left')),
                  ButtonSegment(value: 'right', label: Text('Right')),
                ],
                selected: {_handedness},
                onSelectionChanged: _busy ? null : (s) => setState(() => _handedness = s.first),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _pickAndAnalyze,
                icon: const Icon(Icons.video_file_outlined),
                label: const Text('Pick video…'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_busy) ...[
            LinearProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 8),
            Text('Uploading / analyzing…', style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: AppTheme.danger)),
            ),
          if (_result != null) Expanded(child: _buildResult(_result!)),
        ],
      ),
    );
  }

  Widget _buildResult(AnalysisResult result) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummary(result),
          const SizedBox(height: 20),
          if (result.swings.length > 1) _buildTrajectoryChart(result),
          const SizedBox(height: 20),
          Text('Swings (${result.swings.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...result.swings.asMap().entries.map((e) => _buildSwingTile(result, e.key, e.value)),
        ],
      ),
    );
  }

  Widget _buildSummary(AnalysisResult result) {
    final s = result.summary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _statText('Duration', result.duration != null ? '${result.duration!.toStringAsFixed(1)}s' : '--'),
            _statText('FPS', result.fps?.toStringAsFixed(0) ?? '--'),
            _statText('Handedness', result.handedness ?? '--'),
            _statText('Swings', '${result.swingCount ?? result.swings.length}'),
            _statText('Avg efficiency', s.avgEfficiency?.toStringAsFixed(0) ?? '--',
                color: AppTheme.scoreColor(s.avgEfficiency)),
            _statText('Avg injury risk', s.avgInjuryRisk?.toStringAsFixed(0) ?? '--',
                color: AppTheme.scoreColor(s.avgInjuryRisk, higherIsWorse: true)),
          ],
        ),
      ),
    );
  }

  Widget _statText(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      ],
    );
  }

  Widget _buildTrajectoryChart(AnalysisResult result) {
    final idx = _selectedTrajectorySwingIndex ?? 0;
    final swing = result.swings[idx.clamp(0, result.swings.length - 1)];
    final traj = swing.trajectory;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Swing trajectory', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 12),
                DropdownButton<int>(
                  value: idx,
                  underline: const SizedBox.shrink(),
                  items: List.generate(
                    result.swings.length,
                    (i) => DropdownMenuItem(value: i, child: Text('Swing #${result.swings[i].id ?? i + 1}')),
                  ),
                  onChanged: (v) => setState(() => _selectedTrajectorySwingIndex = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (traj.isEmpty)
              Text('No trajectory data for this swing.', style: Theme.of(context).textTheme.bodySmall)
            else
              SizedBox(
                height: 220,
                child: LineChart(_buildChartData(traj)),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: const [
                _LegendDot(color: Color(0xFFB6F000), label: 'wrist speed'),
                _LegendDot(color: Color(0xFF4BA3FF), label: 'hip rotation speed'),
                _LegendDot(color: Color(0xFFFF5D5D), label: 'shoulder rotation speed'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildChartData(List<TrajectoryPoint> traj) {
    List<FlSpot> spotsFor(double? Function(TrajectoryPoint p) getY) {
      final spots = <FlSpot>[];
      for (final p in traj) {
        final t = p.t;
        final y = getY(p);
        if (t != null && y != null) spots.add(FlSpot(t, y));
      }
      return spots;
    }

    return LineChartData(
      gridData: const FlGridData(show: true, drawVerticalLine: false),
      titlesData: const FlTitlesData(
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 24)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spotsFor((p) => p.wristSpeed),
          color: const Color(0xFFB6F000),
          dotData: const FlDotData(show: false),
          barWidth: 2,
        ),
        LineChartBarData(
          spots: spotsFor((p) => p.hipRotationSpeed),
          color: const Color(0xFF4BA3FF),
          dotData: const FlDotData(show: false),
          barWidth: 2,
        ),
        LineChartBarData(
          spots: spotsFor((p) => p.shoulderRotationSpeed),
          color: const Color(0xFFFF5D5D),
          dotData: const FlDotData(show: false),
          barWidth: 2,
        ),
      ],
    );
  }

  Widget _buildSwingTile(AnalysisResult result, int index, SwingReport swing) {
    final id = swing.id ?? index;
    final expanded = _expandedSwingId == id;
    final keyframeB64 = result.keyframes[swing.id?.toString() ?? '$id'];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          ListTile(
            title: Text('Swing #${swing.id ?? index + 1}'),
            subtitle: Text(
              'Efficiency ${swing.efficiencyScore ?? '--'} · Injury risk ${swing.injuryRiskScore ?? '--'}',
            ),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expandedSwingId = expanded ? null : id),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  if (keyframeB64 != null) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(base64Decode(keyframeB64), fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SwingReportCard(report: swing),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
