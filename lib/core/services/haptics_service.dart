import 'package:flutter/services.dart';

class Haptics {
  bool enabled = true;
  bool keys = false;

  void key() {
    if (enabled && keys) HapticFeedback.selectionClick();
  }

  void wrong() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  void combo() {
    if (enabled) HapticFeedback.mediumImpact();
  }

  void nitro() {
    if (enabled) HapticFeedback.vibrate();
  }

  void finish() {
    if (enabled) HapticFeedback.heavyImpact();
  }

  void light() {
    if (enabled) HapticFeedback.lightImpact();
  }
}
