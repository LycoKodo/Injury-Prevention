import 'dart:async';

import 'package:flutter/material.dart';

import '../models/frame_message.dart';
import '../models/swing_report.dart';
import '../services/app_settings.dart';
import '../services/backend_client.dart';
import '../theme/app_theme.dart';
import '../widgets/coach_card.dart';
import '../widgets/connection_banner.dart';
import '../widgets/metric_gauge.dart';
import '../widgets/skeleton_painter.dart';
import '../widgets/swing_report_card.dart';

class LiveScreen extends StatefulWidget {
  final AppSettings settings;

  const LiveScreen({super.key, required this.settings});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

const String _streamUrlSentinel = '__stream_url__';

class _LiveScreenState extends State<LiveScreen> {
  late BackendClient _client;
  LiveSession? _session;

  List<CameraInfo> _cameras = [];
  String _selectedSource = '0';
  String _model = 'lite';
  String _handedness = 'auto';
  String _aspect = '4:3';
  bool _coach = true;
  bool _coachVoice = true;
  bool _running = false;
  bool _connected = false;
  bool _backendHealthy = false;
  StreamSubscription<HealthStatus?>? _healthSub;

  String? _statusMessage;
  bool _statusIsWarning = false;
  Timer? _statusHideTimer;

  final ValueNotifier<FrameMessage?> _latestFrame = ValueNotifier(null);
  final List<SwingReport> _swings = [];
  final ValueNotifier<SwingReport?> _selectedSwing = ValueNotifier(null);

  StreamSubscription? _frameSub;
  StreamSubscription? _swingSub;
  StreamSubscription? _connSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _statusSub;

  @override
  void initState() {
    super.initState();
    _client = BackendClient(baseUrl: widget.settings.backendUrl);
    _pollHealth();
  }

  void _pollHealth() {
    _healthSub?.cancel();
    _healthSub = _client.pollHealth().listen((status) {
      final healthy = status?.ok ?? false;
      if (mounted) {
        setState(() => _backendHealthy = healthy);
        if (healthy) _loadCameras();
      }
    });
  }

  Future<void> _loadCameras() async {
    try {
      final cams = await _client.cameras();
      if (mounted) {
        setState(() {
          _cameras = cams;
          final validSources = {
            for (final c in cams) c.source,
            if (widget.settings.streamUrl != null) widget.settings.streamUrl!,
          };
          if (!validSources.contains(_selectedSource)) {
            _selectedSource = cams.isNotEmpty ? cams.first.source : '0';
          }
        });
      }
    } catch (_) {
      // Keep camera list empty; UI shows a default entry.
    }
  }

  void _retryHealth() {
    setState(() => _backendHealthy = false);
    _pollHealth();
  }

  void _start() {
    _session?.dispose();
    final session = LiveSession(
      baseUrl: widget.settings.backendUrl,
      camera: _selectedSource,
      aspect: _aspect,
      model: _model,
      handedness: _handedness,
      fps: widget.settings.defaultFps,
      jpegQuality: widget.settings.jpegQuality,
      width: widget.settings.width,
      coach: _coach,
      coachVoice: _coachVoice,
    );
    _frameSub?.cancel();
    _swingSub?.cancel();
    _connSub?.cancel();
    _errorSub?.cancel();
    _statusSub?.cancel();
    _frameSub = session.frames.listen((f) => _latestFrame.value = f);
    _swingSub = session.swings.listen((s) {
      setState(() {
        _swings.insert(0, s);
        _selectedSwing.value = s;
      });
    });
    _connSub = session.connectionState.listen((c) {
      if (mounted) setState(() => _connected = c);
    });
    _errorSub = session.errors.listen((_) {});
    _statusSub = session.statusMessages.listen(_onStatusMessage);
    session.connect();
    setState(() {
      _session = session;
      _running = true;
    });
  }

  void _stop() {
    _session?.dispose();
    _session = null;
    _frameSub?.cancel();
    _swingSub?.cancel();
    _connSub?.cancel();
    _errorSub?.cancel();
    _statusSub?.cancel();
    _statusHideTimer?.cancel();
    _latestFrame.value = null;
    setState(() {
      _running = false;
      _connected = false;
      _statusMessage = null;
    });
  }

  bool _isWarningStatus(String message) {
    final lower = message.toLowerCase();
    return lower.contains('black frame') || lower.contains('center stage');
  }

  void _onStatusMessage(String message) {
    if (!mounted || message.isEmpty) return;
    _statusHideTimer?.cancel();
    final warning = _isWarningStatus(message);
    setState(() {
      _statusMessage = message;
      _statusIsWarning = warning;
    });
    if (!warning) {
      _statusHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _statusMessage = null);
      });
    }
  }

  void _dismissStatus() {
    _statusHideTimer?.cancel();
    setState(() => _statusMessage = null);
  }

  IconData _cameraIcon(String kind) {
    switch (kind) {
      case 'iphone':
        return Icons.phone_iphone;
      case 'builtin':
        return Icons.laptop_mac;
      default:
        return Icons.usb;
    }
  }

  Future<void> _pickStreamUrl() async {
    final controller = TextEditingController(text: widget.settings.streamUrl ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stream URL'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'rtsp://... or http://.../video',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Use URL'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (url != null && url.isNotEmpty && mounted) {
      widget.settings.update(streamUrl: url);
      setState(() => _selectedSource = url);
    }
  }

  void _onCameraChanged(String? value) {
    if (value == null) return;
    if (value == _streamUrlSentinel) {
      _pickStreamUrl();
      return;
    }
    setState(() => _selectedSource = value);
  }

  void _reset() {
    _session?.sendReset();
    setState(() {
      _swings.clear();
      _selectedSwing.value = null;
    });
  }

  @override
  void dispose() {
    _healthSub?.cancel();
    _frameSub?.cancel();
    _swingSub?.cancel();
    _connSub?.cancel();
    _errorSub?.cancel();
    _statusSub?.cancel();
    _statusHideTimer?.cancel();
    _session?.dispose();
    _latestFrame.dispose();
    _selectedSwing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (!_backendHealthy) ConnectionBanner(onRetry: _retryHealth),
        _buildTopBar(),
        const Divider(height: 1),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    if (_statusMessage != null) _buildStatusStrip(),
                    Expanded(child: _VideoArea(frameNotifier: _latestFrame, handedness: _handedness, swingNotifier: _selectedSwing)),
                    _buildSwingStrip(),
                  ],
                ),
              ),
              SizedBox(
                width: 360,
                child: _buildRightPanel(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildCameraPicker(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rescan cameras',
            onPressed: _backendHealthy ? _loadCameras : null,
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'lite', label: Text('Lite')),
              ButtonSegment(value: 'heavy', label: Text('Heavy')),
            ],
            selected: {_model},
            onSelectionChanged: (s) => setState(() => _model = s.first),
          ),
          Tooltip(
            message: '4:3 uses the full sensor height — more of the player fits in frame',
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '4:3', label: Text('4:3')),
                ButtonSegment(value: '16:9', label: Text('16:9')),
              ],
              selected: {_aspect},
              onSelectionChanged: _running ? null : (s) => setState(() => _aspect = s.first),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'auto', label: Text('Auto')),
              ButtonSegment(value: 'left', label: Text('Left')),
              ButtonSegment(value: 'right', label: Text('Right')),
            ],
            selected: {_handedness},
            onSelectionChanged: (s) {
              setState(() => _handedness = s.first);
              _session?.sendSetHandedness(s.first);
            },
          ),
          Tooltip(
            message: 'Speak one or two coaching cues after each swing',
            child: FilterChip(
              avatar: Icon(_coach ? Icons.record_voice_over : Icons.voice_over_off, size: 16),
              label: const Text('Coach'),
              selected: _coach,
              onSelected: _running ? null : (v) => setState(() => _coach = v),
            ),
          ),
          Tooltip(
            message: 'Speak the cues aloud, or keep them text-only',
            child: FilterChip(
              avatar: Icon(_coachVoice ? Icons.volume_up : Icons.volume_off, size: 16),
              label: const Text('Voice'),
              selected: _coachVoice,
              onSelected: (_running || !_coach)
                  ? null
                  : (v) => setState(() => _coachVoice = v),
            ),
          ),
          FilledButton.icon(
            onPressed: !_backendHealthy ? null : (_running ? _stop : _start),
            icon: Icon(_running ? Icons.stop : Icons.play_arrow),
            label: Text(_running ? 'Stop' : 'Start'),
          ),
          OutlinedButton.icon(
            onPressed: _running ? _reset : null,
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset'),
          ),
          if (_running)
            Chip(
              avatar: Icon(_connected ? Icons.wifi : Icons.wifi_off, size: 16),
              label: Text(_connected ? 'Connected' : 'Reconnecting…'),
              backgroundColor: (_connected ? AppTheme.good : AppTheme.warn).withValues(alpha: 0.15),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraPicker() {
    final items = <DropdownMenuItem<String>>[];
    final cams = _cameras.isEmpty
        ? const [CameraInfo(index: 0, name: 'Camera 0', source: '0', kind: 'external')]
        : _cameras;
    for (final c in cams) {
      items.add(DropdownMenuItem(
        value: c.source,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_cameraIcon(c.kind), size: 16),
            const SizedBox(width: 6),
            Text(c.name),
          ],
        ),
      ));
    }
    final streamUrl = widget.settings.streamUrl;
    if (streamUrl != null && streamUrl.isNotEmpty) {
      items.add(DropdownMenuItem(
        value: streamUrl,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_tethering, size: 16),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(streamUrl, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ));
    }
    items.add(const DropdownMenuItem(
      value: _streamUrlSentinel,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_tethering, size: 16),
          SizedBox(width: 6),
          Text('Stream URL…'),
        ],
      ),
    ));

    final validValues = items.map((i) => i.value).toSet();
    final currentValue = validValues.contains(_selectedSource) ? _selectedSource : null;

    return DropdownButton<String>(
      value: currentValue,
      hint: const Text('Camera'),
      underline: const SizedBox.shrink(),
      items: items,
      onChanged: _running ? null : _onCameraChanged,
    );
  }

  Widget _buildStatusStrip() {
    final message = _statusMessage!;
    final color = _statusIsWarning ? AppTheme.warn : AppTheme.courtGreenDim;
    return Material(
      color: color.withValues(alpha: 0.18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(_statusIsWarning ? Icons.warning_amber_rounded : Icons.info_outline, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              tooltip: 'Dismiss',
              splashRadius: 16,
              onPressed: _dismissStatus,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwingStrip() {
    if (_swings.isEmpty) {
      return const SizedBox(height: 100);
    }
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _swings.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = _swings[i];
          return ValueListenableBuilder<SwingReport?>(
            valueListenable: _selectedSwing,
            builder: (context, selected, _) {
              final isSelected = identical(selected, s);
              return InkWell(
                onTap: () => _selectedSwing.value = s,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 96,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppTheme.courtGreen : Colors.white12,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('#${s.id ?? i + 1}', style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 4),
                      Text(
                        'E ${s.efficiencyScore ?? '--'}',
                        style: TextStyle(color: AppTheme.scoreColor(s.efficiencyScore), fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'R ${s.injuryRiskScore ?? '--'}',
                        style: TextStyle(
                          color: AppTheme.scoreColor(s.injuryRiskScore, higherIsWorse: true),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCoachCard() {
    final session = _session;
    if (session == null) {
      return const CoachCard(state: CoachState());
    }
    return ValueListenableBuilder<CoachState>(
      valueListenable: session.coachState,
      builder: (context, state, _) => CoachCard(state: state),
    );
  }

  Widget _buildRightPanel() {
    return Container(
      color: AppTheme.surfaceCard,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCoachCard(),
            const SizedBox(height: 16),
            Text('Live metrics', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ValueListenableBuilder<FrameMessage?>(
              valueListenable: _latestFrame,
              builder: (context, frame, _) {
                final m = frame?.metrics;
                return Column(
                  children: [
                    MetricGauge(label: 'Elbow angle', value: m?.elbowAngle, unit: '°', min: 0, max: 180, targetMin: 100, targetMax: 175),
                    MetricGauge(label: 'Hip-shoulder sep.', value: m?.hipShoulderSeparation, unit: '°', min: 0, max: 90, targetMin: 30, targetMax: 45),
                    MetricGauge(label: 'Knee flexion', value: m?.kneeFlexion, unit: '°', min: 0, max: 90, targetMin: 30, targetMax: 50),
                    MetricGauge(label: 'Shoulder abduction', value: m?.shoulderAbduction, unit: '°', min: 0, max: 150, targetMin: 0, targetMax: 90),
                    MetricGauge(label: 'Trunk lat. flexion', value: m?.trunkLateralFlexion, unit: '°', min: -30, max: 30, targetMin: -20, targetMax: 20),
                    MetricGauge(label: 'Wrist speed', value: m?.wristSpeed, unit: '/s', min: 0, max: 5),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text('Latest swing', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ValueListenableBuilder<SwingReport?>(
              valueListenable: _selectedSwing,
              builder: (context, swing, _) {
                if (swing == null) {
                  return Text('No swings detected yet.', style: Theme.of(context).textTheme.bodySmall);
                }
                return SwingReportCard(report: swing);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoArea extends StatelessWidget {
  final ValueNotifier<FrameMessage?> frameNotifier;
  final ValueNotifier<SwingReport?> swingNotifier;
  final String handedness;

  const _VideoArea({required this.frameNotifier, required this.swingNotifier, required this.handedness});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
          return ValueListenableBuilder<FrameMessage?>(
            valueListenable: frameNotifier,
            builder: (context, frame, _) {
              if (frame == null) {
                return Center(
                  child: Text(
                    'No video — press Start',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white38),
                  ),
                );
              }
              final imageSize = (frame.w != null && frame.h != null)
                  ? Size(frame.w!.toDouble(), frame.h!.toDouble())
                  : containerSize;
              final rect = computeLetterboxRect(containerSize, imageSize);
              return Stack(
                children: [
                  if (frame.jpeg != null)
                    Positioned.fromRect(
                      rect: rect,
                      child: Image.memory(frame.jpeg!, gaplessPlayback: true, fit: BoxFit.fill),
                    ),
                  ValueListenableBuilder<SwingReport?>(
                    valueListenable: swingNotifier,
                    builder: (context, swing, _) {
                      return CustomPaint(
                        size: containerSize,
                        painter: SkeletonPainter(
                          landmarks: frame.landmarks,
                          imageRect: rect,
                          handedness: handedness == 'auto' ? frame.metrics.handedness : handedness,
                          riskByJoint: swing?.riskByJoint,
                        ),
                      );
                    },
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Row(
                      children: [
                        _PhaseChip(phase: frame.phase),
                        const SizedBox(width: 8),
                        if (frame.fps != null) _FpsChip(fps: frame.fps!),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PhaseChip extends StatelessWidget {
  final String? phase;
  const _PhaseChip({required this.phase});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.phaseColor(phase);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        (phase ?? 'idle').replaceAll('_', ' '),
        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }
}

class _FpsChip extends StatelessWidget {
  final double fps;
  const _FpsChip({required this.fps});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('${fps.toStringAsFixed(0)} fps', style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }
}
