import 'package:flutter/material.dart';

import '../services/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;

  const SettingsScreen({super.key, required this.settings});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  late double _fps;
  late double _jpegQuality;
  late double _width;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.settings.backendUrl);
    _fps = widget.settings.defaultFps.toDouble();
    _jpegQuality = widget.settings.jpegQuality.toDouble();
    _width = widget.settings.width.toDouble();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _apply() {
    widget.settings.update(
      backendUrl: _urlController.text.trim(),
      defaultFps: _fps.round(),
      jpegQuality: _jpegQuality.round(),
      width: _width.round(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings applied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),
            Text('Backend URL', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(hintText: 'http://127.0.0.1:8765'),
            ),
            const SizedBox(height: 24),
            _sliderRow('Default FPS', _fps, 5, 30, (v) => setState(() => _fps = v)),
            _sliderRow('JPEG quality', _jpegQuality, 10, 95, (v) => setState(() => _jpegQuality = v)),
            _sliderRow('Frame width', _width, 320, 1280, (v) => setState(() => _width = v)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(onPressed: _apply, child: const Text('Apply')),
            ),
            const SizedBox(height: 24),
            Text(
              'Settings are kept in memory only for this session.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white54),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text('Using an iPhone as the camera', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _helpItem(
              context,
              'Continuity Camera (no setup)',
              'Unlock the iPhone, mount it in landscape near the Mac, then pick "iPhone Camera" in '
                  'the picker. Requires both devices to be signed into the same Apple Account with '
                  'Wi-Fi and Bluetooth on. Turn OFF Center Stage in Control Centre > Video Effects — '
                  'its auto-panning distorts the measurements.',
            ),
            _helpItem(
              context,
              'True ultra-wide (0.5x)',
              'Continuity Camera only exposes the main wide lens. To get the ultra-wide, use an '
                  'iPhone streaming app that can select the 0.5x lens and publish an RTSP/HTTP '
                  'stream, then paste that URL into "Stream URL…" in the camera picker.',
            ),
            _helpItem(
              context,
              'Recorded clips',
              'Film at 0.5x ultra-wide in the iPhone Camera app and use the Analyze Video screen. '
                  'This gives the widest view and the best quality.',
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text('Talking coach', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _helpItem(
              context,
              'What it does',
              'After each detected swing, the coach speaks one or two short cues — a problem and '
                  'a fix — out loud through the Mac\'s speakers. The Live screen also shows the text.',
            ),
            _helpItem(
              context,
              'Capped at 30 seconds',
              'Each spoken line is kept short enough to finish well within 30 seconds, and playback '
                  'is stopped if it ever runs past that.',
            ),
            _helpItem(
              context,
              'Skipped swings are on purpose',
              'If a new swing lands while the coach is still talking about the last one, it is '
                  'skipped rather than queued — timely advice beats a backlog of stale advice.',
            ),
            _helpItem(
              context,
              'Online vs. offline',
              'When Cerebras and ElevenLabs API keys are configured in backend/.env, the text comes '
                  'from Cerebras and the voice from ElevenLabs. Otherwise the coach falls back to '
                  'local rule-based text and the macOS system voice, with no loss of functionality.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpItem(BuildContext context, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(label)),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: (max - min).round(),
              label: value.round().toString(),
              onChanged: onChanged,
            ),
          ),
          SizedBox(width: 48, child: Text(value.round().toString(), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
