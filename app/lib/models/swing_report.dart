import 'feedback.dart';
import 'kinetic_chain.dart';
import 'live_metrics.dart';
import 'trajectory_point.dart';

class SwingReport {
  final int? id;
  final double? tStart;
  final double? tContact;
  final double? tEnd;
  final int? efficiencyScore;
  final int? injuryRiskScore;
  final Map<String, double> riskByJoint;
  final Map<String, double> forceDistribution;
  final Map<String, double> idealDistribution;
  final LiveMetrics metricsAtContact;
  final KineticChain kineticChain;
  final List<Feedback> feedback;
  final List<TrajectoryPoint> trajectory;

  const SwingReport({
    this.id,
    this.tStart,
    this.tContact,
    this.tEnd,
    this.efficiencyScore,
    this.injuryRiskScore,
    this.riskByJoint = const {},
    this.forceDistribution = const {},
    this.idealDistribution = const {},
    this.metricsAtContact = const LiveMetrics(),
    this.kineticChain = const KineticChain(),
    this.feedback = const [],
    this.trajectory = const [],
  });

  static double? _numOrNull(Object? v) => v == null ? null : (v as num).toDouble();
  static int? _intOrNull(Object? v) => v == null ? null : (v as num).toInt();

  static Map<String, double> _mapFromJson(Object? json) {
    if (json == null) return const {};
    final map = json as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  factory SwingReport.fromJson(Map<String, dynamic> json) {
    return SwingReport(
      id: _intOrNull(json['id']),
      tStart: _numOrNull(json['t_start']),
      tContact: _numOrNull(json['t_contact']),
      tEnd: _numOrNull(json['t_end']),
      efficiencyScore: _intOrNull(json['efficiency_score']),
      injuryRiskScore: _intOrNull(json['injury_risk_score']),
      riskByJoint: _mapFromJson(json['risk_by_joint']),
      forceDistribution: _mapFromJson(json['force_distribution']),
      idealDistribution: _mapFromJson(json['ideal_distribution']),
      metricsAtContact: LiveMetrics.fromJson(json['metrics_at_contact'] as Map<String, dynamic>?),
      kineticChain: KineticChain.fromJson(json['kinetic_chain'] as Map<String, dynamic>?),
      feedback: Feedback.listFromJson(json['feedback']),
      trajectory: TrajectoryPoint.listFromJson(json['trajectory']),
    );
  }

  static List<SwingReport> listFromJson(Object? json) {
    if (json == null) return const [];
    final list = json as List<dynamic>;
    return list.map((e) => SwingReport.fromJson(e as Map<String, dynamic>)).toList();
  }
}
