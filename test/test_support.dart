import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/services/audio_service.dart';
import 'package:type_racer_legends/data/local/local_store.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/features/content/content_db.dart';

/// Loads the real seed content from /content for tests.
ContentDb loadSeedContent([void Function(Map<String, dynamic> files)? tweak]) {
  final cat = jsonDecode(File('content/catalog.json').readAsStringSync()) as Map<String, dynamic>;
  final files = <String, dynamic>{'catalog': cat};
  for (final e in (cat['files'] as Map<String, dynamic>).entries) {
    files[e.key] = jsonDecode(File('content/${e.value['path']}').readAsStringSync());
  }
  tweak?.call(files);
  return ContentDb.parse(files);
}

class GameSettingsStub {
  static GameSettings make([Map<String, dynamic>? m]) => GameSettings(m ?? <String, dynamic>{});
}

/// Creates a provider container backed by a temp Hive store and the seed content (for widget tests).
bool _fontsLoaded = false;

/// Loads the bundled fonts so widget tests lay text out like the real app (the default test font is one em wide per glyph).
Future<void> loadTestFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  for (final f in {'Tajawal': ['assets/fonts/Tajawal-Regular.ttf', 'assets/fonts/Tajawal-Bold.ttf'], 'FiraMono': ['assets/fonts/FiraMono-Regular.ttf', 'assets/fonts/FiraMono-Bold.ttf']}.entries) {
    final loader = FontLoader(f.key);
    for (final path in f.value) {
      try {
        loader.addFont(rootBundle.load(path));
      } catch (_) {}
    }
    await loader.load();
  }
}

Future<ProviderContainer> testContainer(WidgetTester tester) async {
  await tester.runAsync(loadTestFonts);
  Directory? tmp;
  final store = await tester.runAsync(() async {
    final dir = tmp = await Directory.systemTemp.createTemp('trl_test');
    return LocalStore.forTest(dir.path);
  });
  addTearDown(() {
    try {
      tmp?.deleteSync(recursive: true); // keep /tmp (tmpfs on CI and in the sandbox) from filling up
    } catch (_) {}
  });
  final c = ProviderContainer(overrides: [
    storeProvider.overrideWithValue(store!),
    initialContentProvider.overrideWithValue(loadSeedContent()),
    audioProvider.overrideWithValue(AudioService()..available = false),
  ]);
  addTearDown(c.dispose);
  return c;
}
