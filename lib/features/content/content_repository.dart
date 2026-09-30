import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../data/local/local_store.dart';
import 'content_db.dart';

/// Loads content: bundled assets first, then newer versions cached in Hive (from the live catalog).
class ContentRepository {
  ContentRepository(this.store);
  final LocalStore store;

  Future<Map<String, dynamic>?> _asset(String path) async {
    try {
      return jsonDecode(await rootBundle.loadString('content/$path')) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('asset $path missing: $e');
      return null;
    }
  }

  Map<String, dynamic>? cachedCatalog() {
    final raw = store.content.get('catalog') as String?;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? cachedFile(String key) {
    final raw = store.content.get('file:$key') as String?;
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  int cachedFileVersion(String key) => (store.content.get('fv:$key') as int?) ?? 0;

  Future<ContentDb> loadLocal() async {
    final bundled = await _asset('catalog.json') ?? <String, dynamic>{};
    final cached = cachedCatalog();
    final useCached = cached != null && ((cached['version'] as num?) ?? 0) >= ((bundled['version'] as num?) ?? 0);
    final catalog = useCached ? cached : bundled;
    final keys = <String>{
      ...((bundled['files'] as Map?)?.keys.cast<String>() ?? const <String>[]),
      if (useCached) ...((cached['files'] as Map?)?.keys.cast<String>() ?? const <String>[]),
    };
    final files = <String, dynamic>{'catalog': catalog};
    for (final k in keys) {
      final bEntry = (bundled['files'] as Map?)?[k] as Map?;
      final bVer = (bEntry?['version'] as num?)?.toInt() ?? 0;
      Map<String, dynamic>? data;
      if (useCached && cachedFileVersion(k) > bVer) data = cachedFile(k);
      if (data == null && bEntry != null) data = await _asset(bEntry['path'] as String);
      data ??= cachedFile(k);
      if (data != null) files[k] = data;
    }
    return ContentDb.parse(files);
  }
}
