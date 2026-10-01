import 'package:flutter/services.dart';

/// Keeps the display on during a race (a phone that dims mid-typing loses the run) and while a
/// large APK update is downloading. Implemented through the app's own `trl/screen` channel, so it
/// needs no plugin and silently no-ops on platforms/tests where the channel is missing.
class ScreenAwake {
  ScreenAwake._();
  static const _channel = MethodChannel('trl/screen');
  static int _holders = 0;

  /// Reference counted: nested calls (race inside an update download) stay awake until all release.
  static Future<void> acquire() async {
    _holders++;
    if (_holders > 1) return;
    await _send(true);
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders > 0) return;
    await _send(false);
  }

  /// Safety net for hot restarts / crashed flows.
  static Future<void> forceRelease() async {
    _holders = 0;
    await _send(false);
  }

  static Future<void> _send(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepOn', {'on': on});
    } catch (_) {
      // Tests, desktop, web or a missing channel: nothing to do.
    }
  }
}
