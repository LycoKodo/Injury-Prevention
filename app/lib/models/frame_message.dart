import 'dart:convert';
import 'dart:typed_data';

import 'landmark.dart';
import 'live_metrics.dart';

/// A decoded "frame" WebSocket message, with the base64 jpeg already decoded to bytes.
class FrameMessage {
  final double? t;
  final int? w;
  final int? h;
  final double? fps;
  final Uint8List? jpeg;
  final List<Landmark>? landmarks;
  final String? phase;
  final LiveMetrics metrics;

  const FrameMessage({
    this.t,
    this.w,
    this.h,
    this.fps,
    this.jpeg,
    this.landmarks,
    this.phase,
    this.metrics = const LiveMetrics(),
  });

  static double? _numOrNull(Object? v) => v == null ? null : (v as num).toDouble();
  static int? _intOrNull(Object? v) => v == null ? null : (v as num).toInt();

  factory FrameMessage.fromJson(Map<String, dynamic> json) {
    Uint8List? jpegBytes;
    final jpegStr = json['jpeg'] as String?;
    if (jpegStr != null && jpegStr.isNotEmpty) {
      try {
        jpegBytes = base64Decode(jpegStr);
      } catch (_) {
        jpegBytes = null;
      }
    }
    return FrameMessage(
      t: _numOrNull(json['t']),
      w: _intOrNull(json['w']),
      h: _intOrNull(json['h']),
      fps: _numOrNull(json['fps']),
      jpeg: jpegBytes,
      landmarks: Landmark.listFromJson(json['landmarks']),
      phase: json['phase'] as String?,
      metrics: LiveMetrics.fromJson(json['metrics'] as Map<String, dynamic>?),
    );
  }
}
