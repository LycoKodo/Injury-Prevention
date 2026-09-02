/// Web/no-dart:io fallback: launching a local process is not possible.
const bool supportsLaunch = false;

Future<bool> launchBackend() async => false;
