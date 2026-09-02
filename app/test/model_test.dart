import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tennis_form/models/analysis_result.dart';
import 'package:tennis_form/models/coach_message.dart';
import 'package:tennis_form/models/frame_message.dart';
import 'package:tennis_form/models/live_metrics.dart';
import 'package:tennis_form/models/swing_report.dart';
import 'package:tennis_form/services/backend_client.dart';

// JSON examples taken directly from docs/PROTOCOL.md.

const liveMetricsJson = '''
{ "elbow_angle": 145.0,
  "shoulder_abduction": 62.0,
  "hip_shoulder_separation": 28.0,
  "knee_flexion": 35.0,
  "trunk_lateral_flexion": 8.0,
  "wrist_extension": 20.0,
  "wrist_speed": 1.8,
  "hip_rotation_speed": 120.0,
  "shoulder_rotation_speed": 180.0,
  "handedness": "right" }
''';

const swingReportJson = '''
{ "id": 1, "t_start": 10.1, "t_contact": 10.6, "t_end": 11.2,
  "efficiency_score": 74,
  "injury_risk_score": 31,
  "risk_by_joint": { "elbow": 40, "shoulder": 25, "wrist": 20, "lower_back": 35, "knee": 10 },
  "force_distribution": { "legs": 18, "hips": 22, "trunk": 20, "shoulder": 22, "arm": 18 },
  "ideal_distribution": { "legs": 20, "hips": 25, "trunk": 20, "shoulder": 20, "arm": 15 },
  "metrics_at_contact": $liveMetricsJson,
  "kinetic_chain": { "hip_peak_t": 10.45, "shoulder_peak_t": 10.52, "arm_peak_t": 10.58,
                     "sequencing_ok": true, "lag_hip_to_shoulder_ms": 70, "lag_shoulder_to_arm_ms": 60 },
  "feedback": [ { "severity": "good", "joint": "elbow", "title": "Arm-dominant swing", "detail": "Hips contributed only 9%..." } ],
  "trajectory": [ { "t": 10.1, "wrist_speed": 0.2, "hip_rotation_speed": 10, "shoulder_rotation_speed": 12, "elbow_angle": 150 } ] }
''';

const frameMessageJson = '''
{ "type": "frame", "t": 12.345, "w": 640, "h": 480, "fps": 19.2,
  "jpeg": "",
  "landmarks": null,
  "phase": "idle",
  "metrics": $liveMetricsJson }
''';

const coachMessageJson = '''
{ "type": "coach", "swing_id": 3, "source": "cerebras",
  "items": [ { "problem": "Your elbow collapsed at contact.", "fix": "Drive through the ball with a firmer arm." } ],
  "text": "the full spoken line", "voice": "pending", "generate_ms": 240 }
''';

const coachMessageTwoItemsJson = '''
{ "type": "coach", "swing_id": 5, "source": "local",
  "items": [
    { "problem": "Elbow collapsed at contact.", "fix": "Drive through with a firmer arm." },
    { "problem": "Hips barely rotated.", "fix": "Load and turn the hips earlier." }
  ],
  "text": "two cues", "voice": "off", "generate_ms": 5 }
''';

const analysisResultJson = '''
{ "duration": 34.2, "fps": 30, "handedness": "right", "swing_count": 6,
  "swings": [$swingReportJson],
  "summary": { "avg_efficiency": 70, "avg_injury_risk": 33,
               "risk_by_joint": { "elbow": 40 },
               "force_distribution": { "legs": 18 },
               "top_feedback": [ { "severity": "warn", "joint": "wrist", "title": "t", "detail": "d" } ] },
  "keyframes": { "1": "" } }
''';

void main() {
  group('LiveMetrics.fromJson', () {
    test('parses all fields', () {
      final m = LiveMetrics.fromJson(jsonDecode(liveMetricsJson) as Map<String, dynamic>);
      expect(m.elbowAngle, 145.0);
      expect(m.wristSpeed, 1.8);
      expect(m.handedness, 'right');
    });

    test('tolerates null', () {
      final m = LiveMetrics.fromJson(null);
      expect(m.elbowAngle, isNull);
      expect(m.handedness, isNull);
    });
  });

  group('SwingReport.fromJson', () {
    test('parses nested fields from PROTOCOL.md example', () {
      final s = SwingReport.fromJson(jsonDecode(swingReportJson) as Map<String, dynamic>);
      expect(s.id, 1);
      expect(s.efficiencyScore, 74);
      expect(s.injuryRiskScore, 31);
      expect(s.riskByJoint['elbow'], 40);
      expect(s.forceDistribution['legs'], 18);
      expect(s.idealDistribution['hips'], 25);
      expect(s.metricsAtContact.elbowAngle, 145.0);
      expect(s.kineticChain.sequencingOk, true);
      expect(s.kineticChain.lagHipToShoulderMs, 70);
      expect(s.feedback, hasLength(1));
      expect(s.feedback.first.title, 'Arm-dominant swing');
      expect(s.trajectory, hasLength(1));
      expect(s.trajectory.first.wristSpeed, 0.2);
    });

    test('tolerates missing optional fields', () {
      final s = SwingReport.fromJson({'id': 2});
      expect(s.id, 2);
      expect(s.efficiencyScore, isNull);
      expect(s.riskByJoint, isEmpty);
      expect(s.feedback, isEmpty);
    });
  });

  group('FrameMessage.fromJson', () {
    test('parses and decodes null landmarks', () {
      final f = FrameMessage.fromJson(jsonDecode(frameMessageJson) as Map<String, dynamic>);
      expect(f.t, 12.345);
      expect(f.w, 640);
      expect(f.phase, 'idle');
      expect(f.landmarks, isNull);
      expect(f.metrics.elbowAngle, 145.0);
    });
  });

  group('CameraInfo.fromJson', () {
    test('parses the new full payload from PROTOCOL.md', () {
      final json = jsonDecode(
        '{"index": 1, "source": "1", "name": "iPhone Camera", "kind": "iphone", "connected": true}',
      ) as Map<String, dynamic>;
      final c = CameraInfo.fromJson(json);
      expect(c.index, 1);
      expect(c.source, '1');
      expect(c.name, 'iPhone Camera');
      expect(c.kind, 'iphone');
      expect(c.connected, true);
    });

    test('tolerates a minimal legacy payload', () {
      final c = CameraInfo.fromJson({'index': 0, 'name': 'Camera 0'});
      expect(c.index, 0);
      expect(c.name, 'Camera 0');
      expect(c.source, '0');
      expect(c.kind, 'external');
      expect(c.connected, true);
    });
  });

  group('CoachMessage.fromJson', () {
    test('parses the exact payload from PROTOCOL.md', () {
      final c = CoachMessage.fromJson(jsonDecode(coachMessageJson) as Map<String, dynamic>);
      expect(c.swingId, 3);
      expect(c.source, 'cerebras');
      expect(c.items, hasLength(1));
      expect(c.items.first.problem, 'Your elbow collapsed at contact.');
      expect(c.items.first.fix, 'Drive through the ball with a firmer arm.');
      expect(c.text, 'the full spoken line');
      expect(c.voice, 'pending');
      expect(c.generateMs, 240);
    });

    test('parses a payload with two items', () {
      final c = CoachMessage.fromJson(jsonDecode(coachMessageTwoItemsJson) as Map<String, dynamic>);
      expect(c.swingId, 5);
      expect(c.source, 'local');
      expect(c.items, hasLength(2));
      expect(c.items[0].problem, 'Elbow collapsed at contact.');
      expect(c.items[1].fix, 'Load and turn the hips earlier.');
      expect(c.voice, 'off');
      expect(c.generateMs, 5);
    });

    test('tolerates a minimal/partial payload', () {
      final c = CoachMessage.fromJson({'type': 'coach', 'swing_id': 7});
      expect(c.swingId, 7);
      expect(c.source, isNull);
      expect(c.items, isEmpty);
      expect(c.text, isNull);
      expect(c.voice, isNull);
      expect(c.generateMs, isNull);
    });

    test('tolerates completely empty payload', () {
      final c = CoachMessage.fromJson(const {});
      expect(c.swingId, isNull);
      expect(c.items, isEmpty);
    });
  });

  group('AnalysisResult.fromJson', () {
    test('parses swings, summary, keyframes', () {
      final a = AnalysisResult.fromJson(jsonDecode(analysisResultJson) as Map<String, dynamic>);
      expect(a.duration, 34.2);
      expect(a.swingCount, 6);
      expect(a.swings, hasLength(1));
      expect(a.summary.avgEfficiency, 70);
      expect(a.summary.topFeedback.first.title, 't');
      expect(a.keyframes['1'], '');
    });
  });
}
