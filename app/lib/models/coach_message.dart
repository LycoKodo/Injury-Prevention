/// A single coaching cue: one observed problem paired with a suggested fix.
class CoachItem {
  final String? problem;
  final String? fix;

  const CoachItem({this.problem, this.fix});

  factory CoachItem.fromJson(Map<String, dynamic> json) {
    return CoachItem(
      problem: json['problem'] as String?,
      fix: json['fix'] as String?,
    );
  }
}

/// A decoded "coach" WebSocket message: the talking coach's cues for one swing.
/// All fields are null-tolerant since the coach is best-effort and any layer
/// (Cerebras, local rules) may be unavailable.
class CoachMessage {
  final int? swingId;
  final String? source; // "cerebras" | "local"
  final List<CoachItem> items;
  final String? text;
  final String? voice; // "pending" | "off"
  final int? generateMs;

  const CoachMessage({
    this.swingId,
    this.source,
    this.items = const [],
    this.text,
    this.voice,
    this.generateMs,
  });

  static int? _intOrNull(Object? v) => v == null ? null : (v as num).toInt();

  factory CoachMessage.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>?;
    return CoachMessage(
      swingId: _intOrNull(json['swing_id']),
      source: json['source'] as String?,
      items: itemsJson == null
          ? const []
          : itemsJson.map((e) => CoachItem.fromJson(e as Map<String, dynamic>)).toList(),
      text: json['text'] as String?,
      voice: json['voice'] as String?,
      generateMs: _intOrNull(json['generate_ms']),
    );
  }
}
