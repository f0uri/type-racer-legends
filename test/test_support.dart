import 'dart:convert';
import 'dart:io';
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
