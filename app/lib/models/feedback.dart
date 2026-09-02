enum FeedbackSeverity { good, warn, danger, unknown }

FeedbackSeverity feedbackSeverityFromString(String? s) {
  switch (s) {
    case 'good':
      return FeedbackSeverity.good;
    case 'warn':
      return FeedbackSeverity.warn;
    case 'danger':
      return FeedbackSeverity.danger;
    default:
      return FeedbackSeverity.unknown;
  }
}

class Feedback {
  final FeedbackSeverity severity;
  final String? joint;
  final String title;
  final String detail;

  const Feedback({
    required this.severity,
    this.joint,
    required this.title,
    required this.detail,
  });

  factory Feedback.fromJson(Map<String, dynamic> json) {
    return Feedback(
      severity: feedbackSeverityFromString(json['severity'] as String?),
      joint: json['joint'] as String?,
      title: (json['title'] as String?) ?? '',
      detail: (json['detail'] as String?) ?? '',
    );
  }

  static List<Feedback> listFromJson(Object? json) {
    if (json == null) return const [];
    final list = json as List<dynamic>;
    return list.map((e) => Feedback.fromJson(e as Map<String, dynamic>)).toList();
  }
}
