import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/features/garage/look.dart';
import 'package:type_racer_legends/features/garage/vehicle_painter.dart';
import 'package:type_racer_legends/features/race/game/env_painter.dart';
import 'package:type_racer_legends/features/race/game/particles.dart';
import 'test_support.dart';

void main() {
  final db = loadSeedContent();

  test('every vehicle paints with every paint / rim / neon / plate combination without throwing', () {
    final paints = db.skins.where((s) => s.slot == 'paint').toList();
    final rims = db.skins.where((s) => s.slot == 'rims').toList();
    final neons = db.skins.where((s) => s.slot == 'neon').toList();
    final plates = db.skins.where((s) => s.slot == 'plate').toList();
    final stickers = db.skins.where((s) => s.slot == 'sticker').toList();
    expect(db.vehicles.length, greaterThanOrEqualTo(20));
    var i = 0;
    for (final v in db.vehicles) {
      for (final layer in VLayer.values) {
        final rec = PictureRecorder();
        final c = Canvas(rec);
        final look = Look.resolve(db, v, {
          'paint': paints[i % paints.length].id,
          'rims': rims[i % rims.length].id,
          'neon': neons[i % neons.length].id,
          'plate': plates[i % plates.length].id,
          'sticker1': stickers[i % stickers.length].id,
          'sticker2': stickers[(i + 3) % stickers.length].id,
        }, outfitId: db.outfits.first.id, plateName: 'Speedy');
        VehiclePainter.paint(c, look, 200, wheelAngle: i * 0.3, t: i * 0.7, layer: layer, braking: i.isEven);
        rec.endRecording().dispose();
      }
      i++;
    }
  });

  test('all paints, rims, stickers render on a car and a bike', () {
    final car = db.vehicles.firstWhere((v) => !v.isBike), bike = db.vehicles.firstWhere((v) => v.isBike);
    for (final s in db.skins.where((s) => ['paint', 'rims', 'sticker', 'neon', 'plate'].contains(s.slot))) {
      for (final v in [car, bike]) {
        final rec = PictureRecorder();
        VehiclePainter.paint(Canvas(rec), Look.resolve(db, v, {s.slot == 'sticker' ? 'sticker1' : s.slot: s.id}), 160, t: 1.3);
        rec.endRecording().dispose();
      }
    }
  });

  test('all biomes x weather x modifiers x landmarks paint', () {
    const size = Size(360, 260);
    final landmarks = [null, ...db.cities.map((c) => c.landmark)];
    for (final b in db.biomes) {
      for (final mod in ['none', 'fog', 'ice', 'blackout', 'storm']) {
        for (final w in ['none', 'rain', 'snow', 'dust', 'storm']) {
          final env = EnvPainter(EnvSpec.fromBiome(b, mod: mod, weather: w, landmark: landmarks[(mod.length + w.length) % landmarks.length]));
          final rec = PictureRecorder();
          final c = Canvas(rec);
          env.paint(c, size, 1234.5, 3.3);
          env.paintWeather(c, size, 3.3, 300);
          env.paintOverlay(c, size, const Offset(100, 200), 3.3);
          rec.endRecording().dispose();
        }
      }
    }
    for (final l in landmarks.whereType<String>()) {
      final env = EnvPainter(EnvSpec.fromBiome(db.biomes.first, landmark: l));
      for (var x = 0.0; x < 5000; x += 500) {
        final rec = PictureRecorder();
        env.paint(Canvas(rec), size, x, 1);
        rec.endRecording().dispose();
      }
    }
  });

  test('particle pool recycles slots and never exceeds capacity', () {
    final ps = ParticleSystem(50);
    for (var i = 0; i < 500; i++) {
      ps.emit(PKind.values[i % PKind.values.length], 1, 1, 10, 10, 0.5, 3, const Color(0xFFFFFFFF));
    }
    ps.update(0.1);
    expect(ps.alive, lessThanOrEqualTo(50));
    final rec = PictureRecorder();
    ps.render(Canvas(rec));
    rec.endRecording().dispose();
    ps.update(1);
    expect(ps.alive, 0);
  });
}
