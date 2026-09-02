/// LiveMetrics — all fields may be null when no pose is detected.
class LiveMetrics {
  final double? elbowAngle;
  final double? shoulderAbduction;
  final double? hipShoulderSeparation;
  final double? kneeFlexion;
  final double? trunkLateralFlexion;
  final double? wristExtension;
  final double? wristSpeed;
  final double? hipRotationSpeed;
  final double? shoulderRotationSpeed;
  final String? handedness;

  const LiveMetrics({
    this.elbowAngle,
    this.shoulderAbduction,
    this.hipShoulderSeparation,
    this.kneeFlexion,
    this.trunkLateralFlexion,
    this.wristExtension,
    this.wristSpeed,
    this.hipRotationSpeed,
    this.shoulderRotationSpeed,
    this.handedness,
  });

  static double? _numOrNull(Object? v) => v == null ? null : (v as num).toDouble();

  factory LiveMetrics.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LiveMetrics();
    return LiveMetrics(
      elbowAngle: _numOrNull(json['elbow_angle']),
      shoulderAbduction: _numOrNull(json['shoulder_abduction']),
      hipShoulderSeparation: _numOrNull(json['hip_shoulder_separation']),
      kneeFlexion: _numOrNull(json['knee_flexion']),
      trunkLateralFlexion: _numOrNull(json['trunk_lateral_flexion']),
      wristExtension: _numOrNull(json['wrist_extension']),
      wristSpeed: _numOrNull(json['wrist_speed']),
      hipRotationSpeed: _numOrNull(json['hip_rotation_speed']),
      shoulderRotationSpeed: _numOrNull(json['shoulder_rotation_speed']),
      handedness: json['handedness'] as String?,
    );
  }
}
