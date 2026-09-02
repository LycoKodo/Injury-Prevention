/// A single MediaPipe pose landmark: [x, y, z, visibility].
class Landmark {
  final double x;
  final double y;
  final double z;
  final double visibility;

  const Landmark({required this.x, required this.y, required this.z, required this.visibility});

  factory Landmark.fromJson(List<dynamic> json) {
    return Landmark(
      x: (json.isNotEmpty ? json[0] as num : 0).toDouble(),
      y: (json.length > 1 ? json[1] as num : 0).toDouble(),
      z: (json.length > 2 ? json[2] as num : 0).toDouble(),
      visibility: (json.length > 3 ? json[3] as num : 0).toDouble(),
    );
  }

  /// Parses the top-level `landmarks` field: a list of 33 [x,y,z,vis] entries, or null.
  static List<Landmark>? listFromJson(Object? json) {
    if (json == null) return null;
    final list = json as List<dynamic>;
    return list.map((e) => Landmark.fromJson(e as List<dynamic>)).toList();
  }
}
