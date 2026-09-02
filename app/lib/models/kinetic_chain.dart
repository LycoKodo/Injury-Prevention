class KineticChain {
  final double? hipPeakT;
  final double? shoulderPeakT;
  final double? armPeakT;
  final bool? sequencingOk;
  final double? lagHipToShoulderMs;
  final double? lagShoulderToArmMs;

  const KineticChain({
    this.hipPeakT,
    this.shoulderPeakT,
    this.armPeakT,
    this.sequencingOk,
    this.lagHipToShoulderMs,
    this.lagShoulderToArmMs,
  });

  static double? _numOrNull(Object? v) => v == null ? null : (v as num).toDouble();

  factory KineticChain.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KineticChain();
    return KineticChain(
      hipPeakT: _numOrNull(json['hip_peak_t']),
      shoulderPeakT: _numOrNull(json['shoulder_peak_t']),
      armPeakT: _numOrNull(json['arm_peak_t']),
      sequencingOk: json['sequencing_ok'] as bool?,
      lagHipToShoulderMs: _numOrNull(json['lag_hip_to_shoulder_ms']),
      lagShoulderToArmMs: _numOrNull(json['lag_shoulder_to_arm_ms']),
    );
  }
}
