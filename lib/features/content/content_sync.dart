import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../../data/local/local_store.dart';
import 'content_db.dart';
import 'content_repository.dart';

class ContentSyncResult {
  final bool updated;
  final bool notModified;
  final int version;
  final List<String> changedFiles;
  final String? error;
  const ContentSyncResult({this.updated = false, this.notModified = false, this.version = 0, this.changedFiles = const [], this.error});
  bool get ok => error == null;
}

/// Downloads live content (content/catalog.json + files) from GitHub Pages.
/// ETag conditional fetch, schema + path validation, SHA-256 check of every file, atomic commit into Hive.
/// Nothing downloaded is ever executed: only JSON data is accepted.
class ContentSync {
  ContentSync(this.store, {http.Client? client, String? baseUrl, this.appVersionCode = 1, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client(),
        baseUrl = (baseUrl ?? AppConfig.contentBaseUrl).replaceAll(RegExp(r'/+$'), '');
  final LocalStore store;
  final http.Client _client;
  final String baseUrl;
  final int appVersionCode;
  final Duration timeout;

  static const maxFileBytes = 3 * 1024 * 1024;
  static final _pathRe = RegExp(r'^[a-z0-9_\-]+(/[a-z0-9_\-]+)*\.json$');
  static final _hashRe = RegExp(r'^[0-9a-f]{64}$');

  String? get etag => store.meta.get('catalog_etag') as String?;

  /// Validates the structure of a catalog. Returns an error string or null.
  static String? validateCatalog(Map<String, dynamic> c, {int appVersionCode = 1}) {
    final schema = c['schema'];
    if (schema is! int || schema > AppConfig.minContentSchema) return 'unsupported schema $schema';
    if (c['version'] is! int || (c['version'] as int) < 1) return 'bad version';
    final minApp = c['minAppVersion'];
    if (minApp is int && minApp > appVersionCode) return 'content needs app >= $minApp';
    final files = c['files'];
    if (files is! Map || files.isEmpty) return 'no files';
    for (final e in files.entries) {
      final v = e.value;
      if (e.key is! String || v is! Map) return 'bad file entry';
      final path = v['path'];
      if (path is! String || !_pathRe.hasMatch(path) || path.contains('..')) return 'unsafe path ${v['path']}';
      if (v['sha256'] is! String || !_hashRe.hasMatch(v['sha256'] as String)) return 'bad hash for ${e.key}';
      if (v['version'] is! int) return 'bad version for ${e.key}';
      final bytes = v['bytes'];
      if (bytes is int && bytes > maxFileBytes) return 'file too large ${e.key}';
    }
    final kill = c['killSwitch'];
    if (kill != null && kill is! Map) return 'bad killSwitch';
    return null;
  }

  Future<http.Response> _get(String url, {Map<String, String>? headers}) => _client.get(Uri.parse(url), headers: headers).timeout(timeout);

  Future<ContentSyncResult> refresh() async {
    try {
      final repo = ContentRepository(store);
      final headers = <String, String>{'Accept': 'application/json'};
      final tag = etag;
      final cached = repo.cachedCatalog();
      if (tag != null && cached != null) headers['If-None-Match'] = tag;
      final res = await _get('$baseUrl/catalog.json', headers: headers);
      if (res.statusCode == 304) return ContentSyncResult(notModified: true, version: (cached?['version'] as int?) ?? 0);
      if (res.statusCode != 200) return ContentSyncResult(error: 'catalog http ${res.statusCode}');
      // the published checksum protects against truncated / tampered responses
      try {
        final sumRes = await _get('$baseUrl/catalog.json.sha256');
        if (sumRes.statusCode == 200) {
          final want = sumRes.body.trim().toLowerCase();
          if (_hashRe.hasMatch(want) && sha256.convert(res.bodyBytes).toString() != want) return const ContentSyncResult(error: 'catalog checksum mismatch');
        }
      } on TimeoutException {
        // checksum file unreachable: per-file hashes below still protect the data
      } catch (_) {}
      final catalog = jsonDecode(utf8.decode(res.bodyBytes));
      if (catalog is! Map<String, dynamic>) return const ContentSyncResult(error: 'catalog is not an object');
      final bad = validateCatalog(catalog, appVersionCode: appVersionCode);
      if (bad != null) return ContentSyncResult(error: bad);
      final bundledVersion = await _bundledVersion(repo);
      final localVersion = [bundledVersion, (cached?['version'] as int?) ?? 0].reduce((a, b) => a > b ? a : b);
      if ((catalog['version'] as int) < localVersion) return ContentSyncResult(notModified: true, version: localVersion); // never roll back
      final files = (catalog['files'] as Map).cast<String, dynamic>();
      final fresh = <String, Map<String, dynamic>>{};
      final changed = <String>[];
      for (final e in files.entries) {
        final key = e.key;
        final entry = (e.value as Map).cast<String, dynamic>();
        final remoteVer = entry['version'] as int;
        final localVer = repo.cachedFileVersion(key);
        final haveCached = repo.cachedFile(key) != null;
        final bundledFileVer = await _bundledFileVersion(repo, key);
        if (remoteVer <= localVer && haveCached) continue;
        if (remoteVer <= bundledFileVer && !haveCached) continue;
        final r = await _get('$baseUrl/${entry['path']}');
        if (r.statusCode != 200) return ContentSyncResult(error: 'file ${entry['path']} http ${r.statusCode}');
        if (r.bodyBytes.length > maxFileBytes) return ContentSyncResult(error: 'file ${entry['path']} too large');
        if (sha256.convert(r.bodyBytes).toString() != entry['sha256']) return ContentSyncResult(error: 'hash mismatch for ${entry['path']}');
        final data = jsonDecode(utf8.decode(r.bodyBytes));
        if (data is! Map<String, dynamic>) return ContentSyncResult(error: '${entry['path']} is not an object');
        fresh[key] = data;
        changed.add(key);
      }
      // trial parse: the complete new content set must load before anything is committed
      if (fresh.isNotEmpty || (cached?['version'] as int?) != catalog['version']) {
        final trialFiles = <String, dynamic>{'catalog': catalog};
        for (final k in files.keys) {
          trialFiles[k] = fresh[k] ?? repo.cachedFile(k) ?? await _bundledFile(repo, k);
        }
        trialFiles.removeWhere((k, v) => v == null);
        final db = ContentDb.parse(trialFiles);
        if (db.vehicles.isEmpty && db.texts.isEmpty && files.containsKey('vehicles')) return const ContentSyncResult(error: 'parsed content is empty');
      }
      for (final e in fresh.entries) {
        await store.content.put('file:${e.key}', jsonEncode(e.value));
        await store.content.put('fv:${e.key}', (files[e.key] as Map)['version']);
      }
      await store.content.put('catalog', jsonEncode(catalog));
      final newTag = res.headers['etag'];
      if (newTag != null) await store.meta.put('catalog_etag', newTag);
      return ContentSyncResult(updated: true, version: catalog['version'] as int, changedFiles: changed);
    } on TimeoutException {
      return const ContentSyncResult(error: 'timeout');
    } catch (e) {
      debugPrint('content sync failed: $e');
      return ContentSyncResult(error: e.toString());
    }
  }

  Future<int> _bundledVersion(ContentRepository repo) async => ((await repo.bundledCatalog())?['version'] as int?) ?? 0;

  Future<int> _bundledFileVersion(ContentRepository repo, String key) async => (((await repo.bundledCatalog())?['files'] as Map?)?[key] as Map?)?['version'] as int? ?? 0;

  Future<Map<String, dynamic>?> _bundledFile(ContentRepository repo, String key) => repo.bundledFile(key);

  void close() => _client.close();
}
