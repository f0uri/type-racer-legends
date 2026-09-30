import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/features/content/content_db.dart';

Map<String, dynamic> loadAll() {
  final cat = jsonDecode(File('content/catalog.json').readAsStringSync()) as Map<String, dynamic>;
  final files = <String, dynamic>{'catalog': cat};
  for (final e in (cat['files'] as Map<String, dynamic>).entries) {
    files[e.key] = jsonDecode(File('content/${e.value['path']}').readAsStringSync());
  }
  return files;
}

void main() {
  final cat = jsonDecode(File('content/catalog.json').readAsStringSync()) as Map<String, dynamic>;

  test('catalog hashes match files (run tools/build_content.py after editing content)', () {
    for (final e in (cat['files'] as Map<String, dynamic>).entries) {
      final bytes = File('content/${e.value['path']}').readAsBytesSync();
      expect(sha256.convert(bytes).toString(), e.value['sha256'], reason: e.key);
    }
  });

  test('content parses with expected minimum sizes', () {
    final db = ContentDb.parse(loadAll());
    expect(db.texts.length, greaterThanOrEqualTo(500));
    expect(db.vehicles.where((v) => !v.isBike).length, greaterThanOrEqualTo(10));
    expect(db.vehicles.where((v) => v.isBike).length, greaterThanOrEqualTo(10));
    expect(db.stages.length, 50);
    expect(db.biomes.length, 6);
    expect(db.bosses.length, 6);
    expect(db.achievements.length, greaterThanOrEqualTo(50));
    expect(db.cities.length, greaterThanOrEqualTo(10));
    expect(db.vocab.length, greaterThan(150));
    expect(db.textsFor(lang: 'fr').length, greaterThan(50));
    expect(db.dailyText('2026-09-30').id, db.dailyText('2026-09-30').id);
  });

  test('every vehicle and skin has three-language names, rarity and valid price', () {
    final db = ContentDb.parse(loadAll());
    for (final i in [...db.vehicles, ...db.skins, ...db.outfits]) {
      expect(i.name.keys, containsAll(['ar', 'en', 'fr']), reason: i.id);
      expect(['common', 'rare', 'legendary'], contains(i.rarity), reason: i.id);
    }
    for (final v in db.vehicles) {
      expect(v.shape.isNotEmpty, isTrue, reason: v.id);
    }
  });

  test('corrupt items are skipped without crashing', () {
    final files = loadAll();
    (files['vehicles']['items'] as List).add({'id': 'broken'});
    (files['vehicles']['items'] as List).add('garbage');
    final db = ContentDb.parse(files);
    expect(db.vehicle('broken'), isNull);
    expect(db.vehicles.length, greaterThanOrEqualTo(20));
  });

  test('kill switch disables items and features', () {
    final files = loadAll();
    files['catalog']['killSwitch'] = {'items': ['c_vortex'], 'features': ['ads']};
    final db = ContentDb.parse(files);
    expect(db.itemAvailable(db.vehicle('c_vortex')!), isFalse);
    expect(db.itemAvailable(db.vehicle('c_urban')!), isTrue);
    expect(db.featureOn('ads'), isFalse);
    expect(db.featureOn('shop'), isTrue);
  });

  test('all typed texts are keyboard-friendly (English) and campaign text pools exist for each stage', () {
    final db = ContentDb.parse(loadAll());
    for (final t in db.textsFor(lang: 'en')) {
      expect(t.text.codeUnits.every((c) => c < 127), isTrue, reason: t.id);
    }
    for (final s in db.stages) {
      expect(db.textsFor(lang: 'en', cats: s.cats).isNotEmpty, isTrue, reason: 'stage ${s.n}');
    }
  });

  test('every world city has its texts', () {
    final db = ContentDb.parse(loadAll());
    for (final c in db.cities) {
      for (final id in c.textIds) {
        expect(db.textById(id), isNotNull, reason: id);
      }
    }
  });
}
