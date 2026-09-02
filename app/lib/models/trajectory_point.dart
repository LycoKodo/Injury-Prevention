class TrajectoryPoint {
  final double? t;
  final double? wristSpeed;
  final double? hipRotationSpeed;
  final double? shoulderRotationSpeed;
  final double? elbowAngle;

  const TrajectoryPoint({
    this.t,
    this.wristSpeed,
    this.hipRotationSpeed,
    this.shoulderRotationSpeed,
    this.elbowAngle,
  });

  static double? _numOrNull(Object? v) => v == null ? null : (v as num).toDouble();

  factory TrajectoryPoint.fromJson(Map<String, dynamic> json) {
    return TrajectoryPoint(
      t: _numOrNull(json['t']),
      wristSpeed: _numOrNull(json['wrist_speed']),
      hipRotationSpeed: _numOrNull(json['hip_rotation_speed']),
      shoulderRotationSpeed: _numOrNull(json['shoulder_rotation_speed']),
      elbowAngle: _numOrNull(json['elbow_angle']),
    );
  }

  static List<TrajectoryPoint> listFromJson(Object? json) {
    if (json == null) return const [];
    final list = json as List<dynamic>;
    return list.map((e) => TrajectoryPoint.fromJson(e as Map<String, dynamic>)).toList();
  }
}
