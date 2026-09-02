import 'dart:io';

/// Native (macOS/desktop) support: attempts to start ../backend/run.sh relative
/// to the app's executable/working directory.
const bool supportsLaunch = true;

Future<bool> launchBackend() async {
  if (!Platform.isMacOS && !Platform.isLinux) return false;
  final candidates = <String>[
    '../backend/run.sh',
    '../../backend/run.sh',
    'backend/run.sh',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (await file.exists()) {
      try {
        await Process.start(
          'bash',
          [path],
          mode: ProcessStartMode.detached,
        );
        return true;
      } catch (_) {
        continue;
      }
    }
  }
  return false;
}
