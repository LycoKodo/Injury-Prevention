import 'package:flutter/material.dart';

import '../models/landmark.dart';
import '../theme/app_theme.dart';

/// Standard MediaPipe Pose 33-landmark connections (subset used for a body skeleton;
/// excludes fine face contour points beyond the basic ones already present in the set).
const List<List<int>> mediaPipePoseConnections = [
  // Face
  [0, 1], [1, 2], [2, 3], [3, 7],
  [0, 4], [4, 5], [5, 6], [6, 8],
  [9, 10],
  // Torso
  [11, 12], [11, 23], [12, 24], [23, 24],
  // Left arm
  [11, 13], [13, 15], [15, 17], [15, 19], [15, 21], [17, 19],
  // Right arm
  [12, 14], [14, 16], [16, 18], [16, 20], [16, 22], [18, 20],
  // Left leg
  [23, 25], [25, 27], [27, 29], [27, 31], [29, 31],
  // Right leg
  [24, 26], [26, 28], [28, 30], [28, 32], [30, 32],
];

const int lShoulder = 11, rShoulder = 12, lElbow = 13, rElbow = 14;
const int lWrist = 15, rWrist = 16, lHip = 23, rHip = 24;
const int lKnee = 25, rKnee = 26, lAnkle = 27, rAnkle = 28;

Set<int> hittingArmLandmarks(String? handedness) {
  if (handedness == 'left') return {lShoulder, lElbow, lWrist};
  return {rShoulder, rElbow, rWrist}; // default/right/auto
}

/// Maps a coarse joint name from risk_by_joint to the landmark indices it covers.
const Map<String, List<int>> jointNameToLandmarks = {
  'elbow': [lElbow, rElbow],
  'shoulder': [lShoulder, rShoulder],
  'wrist': [lWrist, rWrist],
  'knee': [lKnee, rKnee],
  'lower_back': [lHip, rHip],
};

class SkeletonPainter extends CustomPainter {
  final List<Landmark>? landmarks;
  final Rect imageRect;
  final String? handedness;
  final Map<String, double>? riskByJoint;
  final double minVisibility;

  SkeletonPainter({
    required this.landmarks,
    required this.imageRect,
    this.handedness,
    this.riskByJoint,
    this.minVisibility = 0.3,
  });

  Offset _project(Landmark l) {
    return Offset(
      imageRect.left + l.x * imageRect.width,
      imageRect.top + l.y * imageRect.height,
    );
  }

  Color _jointColor(int index) {
    if (riskByJoint == null || riskByJoint!.isEmpty) return AppTheme.courtGreen;
    for (final entry in jointNameToLandmarks.entries) {
      if (entry.value.contains(index) && riskByJoint!.containsKey(entry.key)) {
        return AppTheme.riskColor(riskByJoint![entry.key]!);
      }
    }
    return AppTheme.courtGreen;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lms = landmarks;
    if (lms == null || lms.isEmpty) return;

    // Pose landmarks can fall outside the frame when the model extrapolates a
    // limb it cannot see. Clip to the image so bones never spill into the
    // letterbox bars and imply a body part that was never in view.
    canvas.save();
    canvas.clipRect(imageRect);

    final hittingSet = hittingArmLandmarks(handedness);

    final bonePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final hittingBonePaint = Paint()
      ..color = AppTheme.courtGreen
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final conn in mediaPipePoseConnections) {
      final a = conn[0], b = conn[1];
      if (a >= lms.length || b >= lms.length) continue;
      final la = lms[a], lb = lms[b];
      if (la.visibility < minVisibility || lb.visibility < minVisibility) continue;
      final isHitting = hittingSet.contains(a) && hittingSet.contains(b);
      canvas.drawLine(_project(la), _project(lb), isHitting ? hittingBonePaint : bonePaint);
    }

    for (var i = 0; i < lms.length; i++) {
      final l = lms[i];
      if (l.visibility < minVisibility) continue;
      final isHitting = hittingSet.contains(i);
      final paint = Paint()..color = _jointColor(i);
      final center = _project(l);
      canvas.drawCircle(center, isHitting ? 5.5 : 3.5, paint);
      if (isHitting) {
        canvas.drawCircle(
          center,
          5.5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.handedness != handedness ||
        oldDelegate.riskByJoint != riskByJoint;
  }
}

/// Computes the letterboxed rect within [container] for an image of [imageSize],
/// preserving aspect ratio (contain-fit).
Rect computeLetterboxRect(Size container, Size imageSize) {
  if (imageSize.width <= 0 || imageSize.height <= 0) {
    return Rect.fromLTWH(0, 0, container.width, container.height);
  }
  final containerAspect = container.width / container.height;
  final imageAspect = imageSize.width / imageSize.height;
  double w, h;
  if (imageAspect > containerAspect) {
    w = container.width;
    h = w / imageAspect;
  } else {
    h = container.height;
    w = h * imageAspect;
  }
  final left = (container.width - w) / 2;
  final top = (container.height - h) / 2;
  return Rect.fromLTWH(left, top, w, h);
}
