import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../../data/models/profile.dart';

/// Android home-screen widget (streak + best WPM). Data is written to the widget's shared preferences;
/// the native provider (TypeRacerWidgetProvider) renders it.
class WidgetService {
  static const androidProvider = 'com.typeracerlegends.game.TypeRacerWidgetProvider';

  static Map<String, Object> data(PlayerProfile p) => {
        'streak': p.streak,
        'best_wpm': p.best('best_wpm').round(),
        'level': p.level().level,
        'name': p.name,
      };

  Future<void> update(PlayerProfile p) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      for (final e in data(p).entries) {
        await HomeWidget.saveWidgetData<Object>(e.key, e.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
    } catch (e) {
      debugPrint('widget update failed: $e');
    }
  }
}
