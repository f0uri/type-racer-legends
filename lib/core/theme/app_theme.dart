import 'package:flutter/material.dart';

// ألوان أسطورية بدون نيون — تصميم واقعي بأسلوب C# النظيف
class C {
  static const bg = Color(0xFF0F172A); // خلفية داكنة واقعية
  static const surface = Color(0xFF1E293B);
  static const surface2 = Color(0xFF334155);
  static const cyan = Color(0xFF0EA5E9); // أزرق فولاذي بدل النيون
  static const magenta = Color(0xFF8B5CF6); // بنفسجي هادئ بدل النيون
  static const gold = Color(0xFFF59E0B); // ذهبي دافئ
  static const green = Color(0xFF10B981); // أخضر زمردي
  static const red = Color(0xFFEF4444); // أحمر واقعي
  static const textDim = Color(0xFF94A3B8);
  static const common = Color(0xFF64748B);
  static const rare = Color(0xFF3B82F6);
  static const legendary = Color(0xFFF59E0B);
  static Color rarity(String r) => r == 'legendary' ? legendary : (r == 'rare' ? rare : common);
}

/// Colours used for correct/wrong letters; adapted for colour blindness.
class TypingPalette {
  final Color correct, wrong, pending, current;
  const TypingPalette(this.correct, this.wrong, this.pending, this.current);
  static TypingPalette forMode(String mode) {
    switch (mode) {
      case 'protanopia':
      case 'deuteranopia':
        return const TypingPalette(Color(0xFF4DA3FF), Color(0xFFFFB000), Color(0xFF7C86A8), Color(0xFFFFFFFF));
      case 'tritanopia':
        return const TypingPalette(Color(0xFF00D4AA), Color(0xFFFF5470), Color(0xFF7C86A8), Color(0xFFFFFFFF));
      default:
        return const TypingPalette(Color(0xFF3DDC84), Color(0xFFFF4D6D), Color(0xFF7C86A8), Color(0xFFFFFFFF));
    }
  }
}

ThemeData buildTheme({double fontScale = 1, bool dyslexia = false}) {
  final base = ThemeData.dark(useMaterial3: true);
  final family = dyslexia ? 'OpenDyslexic' : 'Tajawal';
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(primary: C.cyan, secondary: C.magenta, surface: C.surface, error: C.red),
    textTheme: base.textTheme.apply(fontFamily: family, bodyColor: Colors.white, displayColor: Colors.white),
    appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
    snackBarTheme: SnackBarThemeData(backgroundColor: C.surface2, contentTextStyle: TextStyle(fontFamily: family, color: Colors.white), behavior: SnackBarBehavior.floating),
    dialogTheme: DialogThemeData(backgroundColor: C.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.surface),
    switchTheme: SwitchThemeData(thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.cyan : Colors.grey)),
    sliderTheme: const SliderThemeData(activeTrackColor: C.cyan, thumbColor: C.cyan),
  );
}
