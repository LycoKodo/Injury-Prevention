import 'feedback.dart';
import 'swing_report.dart';

class AnalysisSummary {
  final double? avgEfficiency;
  final double? avgInjuryRisk;
  final Map<String, double> riskByJoint;
  final Map<String, double> forceDistribution;
  final List<Feedback> topFeedback;

  const AnalysisSummary({
    this.avgEfficiency,
    this.avgInjuryRisk,
    this.riskByJoint = const {},
    this.forceDistribution = const {},
    this.topFeedback = const [],
  });

  static double? _numOrNull(Object? v) => v == null ? null : (v as num).toDouble();

  static Map<String, double> _mapFromJson(Object? json) {
    if (json == null) return const {};
    final map = json as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  factory AnalysisSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AnalysisSummary();
    return AnalysisSummary(
      avgEfficiency: _numOrNull(json['avg_efficiency']),
      avgInjuryRisk: _numOrNull(json['avg_injury_risk']),
      riskByJoint: _mapFromJson(json['risk_by_joint']),
      forceDistribution: _mapFromJson(json['force_distribution']),
      topFeedback: Feedback.listFromJson(json['top_feedback']),
    );
  }
}

class AnalysisResult {
  final double? duration;
  final double? fps;
  final String? handedness;
  final int? swingCount;
  final List<SwingReport> swings;
  final AnalysisSummary summary;
  final Map<String, String> keyframes;

  const AnalysisResult({
    this.duration,
    this.fps,
    this.handedness,
    this.swingCount,
    this.swings = const [],
    this.summary = const AnalysisSummary(),
    this.keyframes = const {},
  });

  static double? _numOrNull(Object? v) => v == null ? null : (v as num).toDouble();
  static int? _intOrNull(Object? v) => v == null ? null : (v as num).toInt();

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    Map<String, String> keyframes = const {};
    if (json['keyframes'] != null) {
      final map = json['keyframes'] as Map<String, dynamic>;
      keyframes = map.map((k, v) => MapEntry(k, v as String));
    }
    return AnalysisResult(
      duration: _numOrNull(json['duration']),
      fps: _numOrNull(json['fps']),
      handedness: json['handedness'] as String?,
      swingCount: _intOrNull(json['swing_count']),
      swings: SwingReport.listFromJson(json['swings']),
      summary: AnalysisSummary.fromJson(json['summary'] as Map<String, dynamic>?),
      keyframes: keyframes,
    );
  }
}
