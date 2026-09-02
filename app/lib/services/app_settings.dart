import 'package:flutter/foundation.dart';

/// In-memory app settings (no persistence package per spec).
class AppSettings extends ChangeNotifier {
  String backendUrl;
  int defaultFps;
  int jpegQuality;
  int width;

  /// Last stream URL entered via the Live screen's "Stream URL…" picker entry,
  /// kept in memory so it survives switching screens.
  String? streamUrl;

  AppSettings({
    this.backendUrl = 'http://127.0.0.1:8765',
    this.defaultFps = 20,
    this.jpegQuality = 60,
    this.width = 640,
    this.streamUrl,
  });

  void update({String? backendUrl, int? defaultFps, int? jpegQuality, int? width, String? streamUrl}) {
    if (backendUrl != null) this.backendUrl = backendUrl;
    if (defaultFps != null) this.defaultFps = defaultFps;
    if (jpegQuality != null) this.jpegQuality = jpegQuality;
    if (width != null) this.width = width;
    if (streamUrl != null) this.streamUrl = streamUrl;
    notifyListeners();
  }
}
