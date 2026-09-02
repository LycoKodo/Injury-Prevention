import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/analysis_result.dart';
import '../models/coach_message.dart';
import '../models/frame_message.dart';
import '../models/swing_report.dart';

class CameraInfo {
  final int index;
  final String name;
  final String source;
  final String kind;
  final bool connected;
  const CameraInfo({
    required this.index,
    required this.name,
    required this.source,
    this.kind = 'external',
    this.connected = true,
  });

  factory CameraInfo.fromJson(Map<String, dynamic> json) {
    final index = (json['index'] as num?)?.toInt() ?? 0;
    return CameraInfo(
      index: index,
      name: (json['name'] as String?) ?? 'Camera',
      source: (json['source'] as String?) ?? index.toString(),
      kind: (json['kind'] as String?) ?? 'external',
      connected: (json['connected'] as bool?) ?? true,
    );
  }
}

class HealthStatus {
  final bool ok;
  final String? model;
  final String? version;
  const HealthStatus({required this.ok, this.model, this.version});

  factory HealthStatus.fromJson(Map<String, dynamic> json) {
    return HealthStatus(
      ok: json['ok'] as bool? ?? false,
      model: json['model'] as String?,
      version: json['version'] as String?,
    );
  }
}

/// REST + health-poll client for the local backend.
class BackendClient {
  String baseUrl;

  BackendClient({this.baseUrl = 'http://127.0.0.1:8765'});

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(path: path, queryParameters: query);
  }

  Future<HealthStatus> health() async {
    final resp = await http.get(_uri('/health')).timeout(const Duration(seconds: 3));
    if (resp.statusCode != 200) {
      throw Exception('health check failed: ${resp.statusCode}');
    }
    return HealthStatus.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Polls /health every [interval] until it succeeds, emitting each attempt's result
  /// (or null on failure) so the UI can show connecting/failed state, and stopping once healthy.
  Stream<HealthStatus?> pollHealth({Duration interval = const Duration(seconds: 2)}) async* {
    while (true) {
      try {
        final status = await health();
        yield status;
        if (status.ok) return;
      } catch (_) {
        yield null;
      }
      await Future.delayed(interval);
    }
  }

  Future<List<CameraInfo>> cameras() async {
    final resp = await http.get(_uri('/cameras')).timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      throw Exception('cameras failed: ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (json['cameras'] as List<dynamic>?) ?? const [];
    return list.map((e) => CameraInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AnalysisResult> analyzeVideo(
    String filePath, {
    String handedness = 'auto',
    String model = 'lite',
    void Function(double progress)? onProgress,
  }) async {
    final uri = _uri('/analyze');
    final request = http.MultipartRequest('POST', uri)
      ..fields['handedness'] = handedness
      ..fields['model'] = model
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamedResponse = await request.send();
    final bytesBuilder = BytesBuilder();
    final total = streamedResponse.contentLength ?? 0;
    var received = 0;
    await for (final chunk in streamedResponse.stream) {
      bytesBuilder.add(chunk);
      received += chunk.length;
      if (total > 0 && onProgress != null) {
        onProgress(received / total);
      }
    }
    final body = utf8.decode(bytesBuilder.takeBytes());
    if (streamedResponse.statusCode != 200) {
      throw Exception('analyze failed: ${streamedResponse.statusCode} $body');
    }
    return AnalysisResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }
}

/// UI-facing rollup of the talking coach's state, folding together the "coach",
/// "coach_spoken" and "coach_skipped" messages so the Live screen can watch a
/// single notifier instead of three separate streams.
class CoachState {
  /// The most recent "coach" message, if any has arrived this session.
  final CoachMessage? message;

  /// True from the moment a "coach" message arrives until its matching
  /// "coach_spoken" is received (i.e. the backend is still playing audio).
  final bool speaking;

  /// The voice that spoke the most recent cue ("elevenlabs" | "system" | "off" | "none").
  final String? lastVoice;

  /// swing_id of the most recent "coach_skipped" message, if the latest coach-related
  /// event was a skip rather than a spoken cue.
  final int? skippedSwingId;

  const CoachState({this.message, this.speaking = false, this.lastVoice, this.skippedSwingId});

  CoachState copyWith({
    CoachMessage? message,
    bool? speaking,
    String? lastVoice,
    int? skippedSwingId,
    bool clearSkipped = false,
  }) {
    return CoachState(
      message: message ?? this.message,
      speaking: speaking ?? this.speaking,
      lastVoice: lastVoice ?? this.lastVoice,
      skippedSwingId: clearSkipped ? null : (skippedSwingId ?? this.skippedSwingId),
    );
  }
}

/// Manages a single WebSocket connection to /ws/live, decoding frame/swing/status/error
/// messages and reconnecting automatically on drop.
class LiveSession {
  final String baseUrl;

  /// Either a device index/source string (e.g. "1") or a stream URL
  /// (contains "://", e.g. "rtsp://..." or "http://.../video").
  String camera;
  String aspect;
  String model;
  String handedness;
  final int fps;
  final int jpegQuality;
  final int width;
  bool coach;
  bool coachVoice;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  bool _closedByUser = false;
  Timer? _reconnectTimer;

  final _frameController = StreamController<FrameMessage>.broadcast();
  final _swingController = StreamController<SwingReport>.broadcast();
  final _statusController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _coachController = StreamController<CoachMessage>.broadcast();

  final ValueNotifier<CoachState> coachState = ValueNotifier(const CoachState());

  Stream<FrameMessage> get frames => _frameController.stream;
  Stream<SwingReport> get swings => _swingController.stream;
  Stream<String> get statusMessages => _statusController.stream;
  Stream<String> get errors => _errorController.stream;
  Stream<bool> get connectionState => _connectionController.stream;
  Stream<CoachMessage> get coachMessages => _coachController.stream;

  LiveSession({
    required this.baseUrl,
    this.camera = '0',
    this.aspect = '4:3',
    this.model = 'lite',
    this.handedness = 'auto',
    this.fps = 20,
    this.jpegQuality = 60,
    this.width = 640,
    this.coach = true,
    this.coachVoice = true,
  });

  Uri get _wsUri {
    final httpUri = Uri.parse(baseUrl);
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    final query = <String, String>{
      'model': model,
      'handedness': handedness,
      'aspect': aspect,
      'fps': '$fps',
      'jpeg_quality': '$jpegQuality',
      'width': '$width',
      'coach': coach ? '1' : '0',
      'coach_voice': coachVoice ? '1' : '0',
    };
    if (camera.contains('://')) {
      query['source'] = camera;
    } else {
      query['camera'] = camera;
    }
    return Uri(
      scheme: scheme,
      host: httpUri.host,
      port: httpUri.port,
      path: '/ws/live',
      queryParameters: query,
    );
  }

  void connect() {
    _closedByUser = false;
    _reconnectTimer?.cancel();
    // Tear down any existing socket first. Without this a reconnect can leave the
    // previous socket open, and the backend would hold a second capture on the
    // same camera — which yields black frames on a Continuity Camera iPhone.
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    try {
      _channel = WebSocketChannel.connect(_wsUri);
      _sub = _channel!.stream.listen(
        _onData,
        onError: (Object err) {
          _connectionController.add(false);
          _scheduleReconnect();
        },
        onDone: () {
          _connectionController.add(false);
          if (!_closedByUser) _scheduleReconnect();
        },
        cancelOnError: true,
      );
      _connectionController.add(true);
    } catch (_) {
      _connectionController.add(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closedByUser) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), connect);
  }

  void _onData(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String?;
      switch (type) {
        case 'frame':
          _frameController.add(FrameMessage.fromJson(json));
          break;
        case 'swing':
          final swingJson = json['swing'] as Map<String, dynamic>?;
          if (swingJson != null) {
            _swingController.add(SwingReport.fromJson(swingJson));
          }
          break;
        case 'status':
          _statusController.add((json['message'] as String?) ?? '');
          break;
        case 'error':
          _errorController.add((json['message'] as String?) ?? 'unknown error');
          break;
        case 'coach':
          final coachMsg = CoachMessage.fromJson(json);
          _coachController.add(coachMsg);
          coachState.value = coachState.value.copyWith(
            message: coachMsg,
            speaking: true,
            clearSkipped: true,
          );
          break;
        case 'coach_spoken':
          coachState.value = coachState.value.copyWith(
            speaking: false,
            lastVoice: (json['voice'] as String?) ?? coachState.value.lastVoice,
          );
          break;
        case 'coach_skipped':
          final skippedId = (json['swing_id'] as num?)?.toInt();
          coachState.value = coachState.value.copyWith(skippedSwingId: skippedId);
          break;
      }
    } catch (_) {
      // Ignore malformed messages rather than crashing the stream.
    }
  }

  void sendSetHandedness(String handedness) {
    this.handedness = handedness;
    _send({'type': 'set', 'handedness': handedness});
  }

  void sendReset() {
    _send({'type': 'reset'});
  }

  void _send(Map<String, dynamic> message) {
    try {
      _channel?.sink.add(jsonEncode(message));
    } catch (_) {
      // Connection likely dropped; reconnect logic will handle it.
    }
  }

  void reconnectWith({
    String? camera,
    String? model,
    String? handedness,
    String? aspect,
    bool? coach,
    bool? coachVoice,
  }) {
    if (camera != null) this.camera = camera;
    if (model != null) this.model = model;
    if (handedness != null) this.handedness = handedness;
    if (aspect != null) this.aspect = aspect;
    if (coach != null) this.coach = coach;
    if (coachVoice != null) this.coachVoice = coachVoice;
    close();
    connect();
  }

  void close() {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }

  void dispose() {
    _closedByUser = true;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _frameController.close();
    _swingController.close();
    _statusController.close();
    _errorController.close();
    _connectionController.close();
    _coachController.close();
    coachState.dispose();
  }
}
