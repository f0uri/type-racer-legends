import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/features/career/campaign_screen.dart';
import 'package:type_racer_legends/features/career/daily_screen.dart';
import 'package:type_racer_legends/features/career/progress_screen.dart';
import 'package:type_racer_legends/features/garage/garage_screen.dart';
import 'package:type_racer_legends/features/home/home_shell.dart';
import 'package:type_racer_legends/features/leaderboard/leaderboard_screen.dart';
import 'package:type_racer_legends/features/profile/profile_screen.dart';
import 'package:type_racer_legends/features/settings/settings_screen.dart';
import 'package:type_racer_legends/features/shop/shop_screen.dart';
import 'test_support.dart';

/// Every screen on every phone size we support.
///
/// Widget tests run at one size only, which is exactly why the first real test run found overflow
/// bugs nobody had seen: a bottom sheet 99px too tall on a 360x733 phone and two hint rows 51/64px
/// too wide. This sweep renders the whole app at the three sizes that matter (a short old phone,
/// a current one, and a large one) and fails on the first layout exception — so the next overflow
/// is caught by CI instead of by a player.
///
/// Android 7 (API 24) devices in the wild still include 360x640 logical pixels; the largest common
/// phone today is around 412x915.
const _sizes = <String, Size>{
  'small 360x640': Size(360, 640),
  'phone 360x800': Size(360, 800),
  'large 412x915': Size(412, 915),
};

void main() {
  final screens = <String, Widget Function()>{
    'الرئيسية (الشل)': () => const HomeShell(),
    'الحملة': () => const CampaignScreen(),
    'المهام اليومية': () => const DailyScreen(),
    'التقدم': () => const ProgressScreen(embedded: false),
    'الكراج': () => const GarageScreen(),
    'المتجر': () => const ShopScreen(),
    'الإعدادات': () => const SettingsScreen(),
    'ملفي': () => const ProfileScreen(),
    'المتصدرون': () => const LeaderboardScreen(),
  };

  for (final size in _sizes.entries) {
    for (final screen in screens.entries) {
      testWidgets('${screen.key} @ ${size.key}', (t) async {
        final c = await testContainer(t);
        t.view.physicalSize = size.value * 3;
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        await t.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp(theme: buildTheme(), home: Directionality(textDirection: TextDirection.rtl, child: screen.value())),
        ));
        // a few frames so late first-frame work (dialogs, carousels, tickers) has run
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 120));
        }
        _check(t, screen.key, size.key, 'layout');
        // and one scroll, because content that only appears after a fling is where overflow hides
        await t.drag(find.byType(Scrollable).first, const Offset(0, -220));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 120));
        }
        _check(t, screen.key, size.key, 'scroll');
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}

/// Reports the failure in one line, then fails. CI logs are not readable from the sandbox that
/// writes this test, so the message has to carry the exception text itself.
void _check(WidgetTester t, String screen, String size, String phase) {
  final err = t.takeException();
  if (err == null) return;
  final text = err.toString().split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).take(6).join(' | ');
  // ignore: avoid_print
  print('LAYOUT_FAIL $screen @ $size [$phase] :: $text');
  fail('$screen at $size threw during $phase: $err');
}
