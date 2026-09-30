import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/features/garage/garage_screen.dart';
import 'package:type_racer_legends/features/home/home_shell.dart';
import 'package:type_racer_legends/features/shop/chest_open_screen.dart';
import 'package:type_racer_legends/features/shop/economy.dart';
import 'package:type_racer_legends/features/shop/shop_screen.dart';
import 'screens_smoke_test.dart' show show;
import 'test_support.dart';
import 'dart:math';

void main() {
  testWidgets('garage: tabs, slots, upgrade, buying and equipping', (t) async {
    final c = await testContainer(t);
    c.read(profileProvider.notifier).update((p) {
      p.addCoins(200000);
      p.addGems(2000);
      p.addXp(100000);
    });
    await show(t, c, const GarageScreen());
    expect(find.text('الكراج'), findsOneWidget);
    // performance tab: upgrade acceleration
    expect(find.textContaining('ترقية'), findsWidgets);
    await t.tap(find.textContaining('ترقية').first);
    await t.pump(const Duration(milliseconds: 300));
    expect(c.read(profileProvider).upgradeLevel('c_sprout', 'accel'), 1);
    // customise tab: walk every slot
    await t.tap(find.text('التخصيص'));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    expect(find.byKey(const Key('slotChips')), findsOneWidget);
    Future<void> reveal(String label) async {
      for (final dir in [-1.0, 1.0]) {
        for (var i = 0; i < 8 && find.textContaining(label).evaluate().isEmpty; i++) {
          await t.drag(find.byKey(const Key('slotChips')), Offset(dir * 220, 0), warnIfMissed: false);
          await t.pump(const Duration(milliseconds: 200));
        }
      }
    }

    for (final label in ['الإطارات', 'نيون', 'العادم', 'لهب النيترو', 'ملصق 1', 'ملصق 2', 'اللوحة', 'البوق', 'الاحتفال', 'الطلاء']) {
      await reveal(label);
      expect(find.textContaining(label), findsWidgets, reason: label);
      await t.tap(find.textContaining(label).first, warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 500));
    }
    // buy + equip a paint
    final db = c.read(contentProvider);
    final p = c.read(profileProvider);
    final buyable = Economy.skinsFor(db, p, db.starterCar, 'paint').firstWhere((s) => !Economy.ownsSkin(p, s) && Economy.availability(db, p, s).canBuy);
    Economy.equip(p, db.starterCar, 'paint', 'p_red');
    await t.tap(find.textContaining('الطلاء').first, warnIfMissed: false);
    await t.pump(const Duration(milliseconds: 400));
    expect(buyable.id, isNotEmpty);
    // switch to bikes and to the outfit tab
    await t.tap(find.textContaining('دراجات'));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('الزي'));
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('الأداء'));
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('shop: deals, chests with transparent odds and opening animation', (t) async {
    final c = await testContainer(t);
    c.read(profileProvider.notifier).update((p) {
      p.addCoins(50000);
      p.addGems(500);
      p.addXp(100000);
    });
    await show(t, c, const ShopScreen());
    expect(find.text('🔥 عروض اليوم'), findsOneWidget);
    expect(find.textContaining('%)'), findsWidgets);
    final db = c.read(contentProvider);
    final def = (db.shop['chests'] as List).cast<Map<String, dynamic>>().first;
    ChestReward? rw;
    c.read(profileProvider.notifier).update((p) {
      Economy.grantChest(p, def['id'] as String);
      rw = Chests.open(db, p, def, Random(9));
    });
    await show(t, c, ChestOpenScreen(def: def, reward: rw!));
    for (var i = 0; i < 60; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('رائع!'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('home shell switches between race, garage and shop tabs', (t) async {
    final c = await testContainer(t);
    await show(t, c, const HomeShell());
    await t.tap(find.text('الكراج').last);
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.text('المتجر').last);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('🔥 عروض اليوم'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
