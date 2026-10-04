import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0B0F1E);
  static const surface = Color(0xFF151B33);
  static const surface2 = Color(0xFF1D2547);
  static const cyan = Color(0xFF00E5FF);
  static const magenta = Color(0xFFFF2BD6);
  static const gold = Color(0xFFFFD166);
  static const green = Color(0xFF3DDC84);
  static const red = Color(0xFFFF4D6D);
  static const textDim = Color(0xFF9AA4C7);
  static const common = Color(0xFF8FA3C8);
  static const rare = Color(0xFF6C8CFF);
  static const legendary = Color(0xFFFFB627);
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

/// The display face: heavier and wider than the body font, used for screen titles and hero
/// numbers so hierarchy is visible at a glance (a game, not a settings page).
const kDisplayFont = 'Almarai';

/// A title style every screen can share. [size] sets the scale, the rest is identity.
TextStyle displayStyle({double size = 20, Color color = Colors.white, double spacing = 0.2}) =>
    TextStyle(fontFamily: kDisplayFont, fontSize: size, fontWeight: FontWeight.w800, color: color, letterSpacing: spacing);

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
