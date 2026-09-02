import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'backend_launcher_stub.dart'
    if (dart.library.io) 'backend_launcher_io.dart' as launcher;

/// Shown when the backend /health check is failing. Offers a Retry button,
/// and on macOS (non-web) a "Launch backend" button that runs ../backend/run.sh.
class ConnectionBanner extends StatefulWidget {
  final VoidCallback onRetry;

  const ConnectionBanner({super.key, required this.onRetry});

  @override
  State<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<ConnectionBanner> {
  bool _launching = false;
  String? _launchMessage;

  Future<void> _launchBackend() async {
    setState(() {
      _launching = true;
      _launchMessage = null;
    });
    try {
      final ok = await launcher.launchBackend();
      setState(() {
        _launchMessage = ok
            ? 'Launched backend/run.sh — retry in a few seconds.'
            : 'Could not launch backend/run.sh automatically.';
      });
    } catch (e) {
      setState(() => _launchMessage = 'Launch failed: $e');
    } finally {
      setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLaunch = !kIsWeb && launcher.supportsLaunch;
    return Material(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _launchMessage ?? 'Backend not reachable — run backend/run.sh',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            if (canLaunch)
              TextButton(
                onPressed: _launching ? null : _launchBackend,
                child: Text(_launching ? 'Launching…' : 'Launch backend'),
              ),
            const SizedBox(width: 4),
            FilledButton(onPressed: widget.onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
