import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/features/race/ui/result_screen.dart';

/// The result headline is the moment the player looks for after every race, so it moves: it drops
/// in with an overshoot instead of appearing. These tests pin both halves of that: it *does* move
/// by default, and it does not move at all when the OS asks for reduced motion.
Widget _host(Widget child) => MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: Directionality(textDirection: TextDirection.rtl, child: child)),
    );

double _bannerOpacity(WidgetTester t) =>
    t.widget<Opacity>(find.descendant(of: find.byType(ResultBanner), matching: find.byType(Opacity))).opacity;

void main() {
  testWidgets('the banner drops in instead of appearing fully formed', (t) async {
    await t.pumpWidget(_host(const ResultBanner(title: 'فوز!', color: C.gold, celebrate: true)));
    expect(_bannerOpacity(t), lessThan(0.5), reason: 'the first frame must still be on its way in');
    final start = t.getTopLeft(find.text('فوز!'));
    await t.pump(const Duration(milliseconds: 120));
    expect(t.getTopLeft(find.text('فوز!')).dy, greaterThan(start.dy), reason: 'the card travels down into place');
    await t.pump(const Duration(milliseconds: 600));
    expect(_bannerOpacity(t), 1.0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('reduced motion shows the banner fully on the first frame', (t) async {
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(_host(const ResultBanner(title: 'فوز!', color: C.gold, celebrate: true)));
    expect(_bannerOpacity(t), 1.0);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('the chain and photo-finish lines ride along with the title', (t) async {
    await t.pumpWidget(_host(const ResultBanner(title: 'فوز!', color: C.gold, chain: 4, photoFinish: true)));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('فوز!'), findsOneWidget);
    expect(find.text('سلسلة الجولات: 4'), findsOneWidget);
    expect(find.text('Photo Finish!'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('a plain result carries no chain and no finish line', (t) async {
    await t.pumpWidget(_host(const ResultBanner(title: 'اكتمل السباق', color: Colors.white)));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.text('اكتمل السباق'), findsOneWidget);
    expect(find.textContaining('سلسلة الجولات'), findsNothing);
    expect(find.text('Photo Finish!'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
