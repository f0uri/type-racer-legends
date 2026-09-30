import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/services/audio_service.dart';
import 'package:type_racer_legends/data/local/local_store.dart';
import 'package:type_racer_legends/core/providers.dart';
import 'package:type_racer_legends/features/content/content_db.dart';

/// Loads the real seed content from /content for tests.
ContentDb loadSeedContent() {
  final cat = jsonDecode(File('content/catalog.json').readAsStringSync()) as Map<String, dynamic>;
  final files = <String, dynamic>{'catalog': cat};
  for (final e in (cat['files'] as Map<String, dynamic>).entries) {
    files[e.key] = jsonDecode(File('content/${e.value['path']}').readAsStringSync());
  }
  return ContentDb.parse(files);
}

class GameSettingsStub {
  static GameSettings make([Map<String, dynamic>? m]) => GameSettings(m ?? <String, dynamic>{});
}

/// Creates a provider container backed by a temp Hive store and the seed content (for widget tests).
Future<ProviderContainer> testContainer(WidgetTester tester) async {
  final store = await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('trl_test');
    return LocalStore.forTest(dir.path);
  });
  final c = ProviderContainer(overrides: [
    storeProvider.overrideWithValue(store!),
    initialContentProvider.overrideWithValue(loadSeedContent()),
    audioProvider.overrideWithValue(AudioService()..available = false),
  ]);
  addTearDown(c.dispose);
  return c;
}
