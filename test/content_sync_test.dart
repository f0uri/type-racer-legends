import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:type_racer_legends/data/local/local_store.dart';
import 'package:type_racer_legends/features/content/content_repository.dart';
import 'package:type_racer_legends/features/content/content_sync.dart';

/// In-memory "GitHub Pages" served from a local HTTP server.
class FakePages {
  final files = <String, List<int>>{};
  final hits = <String>[];
  late HttpServer server;
  String get base => 'http://127.0.0.1:${server.port}/content';

  Future<void> start() async {
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final path = req.uri.path.replaceFirst('/content/', '');
      hits.add(path);
      final body = files[path];
      if (body == null) {
        req.response.statusCode = 404;
      } else {
        final tag = '"${sha256.convert(body).toString().substring(0, 16)}"';
        if (req.headers.value('if-none-match') == tag) {
          req.response.statusCode = 304;
        } else {
          req.response.headers.set('etag', tag);
          req.response.add(body);
        }
      }
      await req.response.close();
    });
  }

  void put(String path, Object json) => files[path] = utf8.encode(jsonEncode(json));

  /// Publishes a catalog (and its .sha256) built from [fileMap] (key -> json) with the given versions.
  void publish(Map<String, Map<String, dynamic>> fileMap, {required int version, Map<String, int>? fileVersions, Map<String, dynamic>? extra, bool badHash = false}) {
    final entries = <String, dynamic>{};
    fileMap.forEach((k, v) {
      final bytes = utf8.encode(jsonEncode(v));
      files['$k.json'] = bytes;
      entries[k] = {'path': '$k.json', 'version': fileVersions?[k] ?? version, 'sha256': badHash ? '0' * 64 : sha256.convert(bytes).toString(), 'bytes': bytes.length};
    });
    final cat = {'schema': 1, 'version': version, 'minAppVersion': 1, 'killSwitch': {'features': [], 'items': []}, 'files': entries, ...?extra};
    final raw = utf8.encode(jsonEncode(cat));
    files['catalog.json'] = raw;
    files['catalog.json.sha256'] = utf8.encode(sha256.convert(raw).toString());
  }
}

Map<String, dynamic> vehicleFile(List<Map<String, dynamic>> items) => {'version': 1, 'items': items};
Map<String, dynamic> v(String id) => {
      'id': id,
      'type': 'vehicle',
      'kind': 'car',
      'style': 'hatch',
      'name': {'ar': 'تجريبية', 'en': 'Test'},
      'rarity': 'rare',
      'price': {'coins': 100},
      'unlock': {},
      'stats': {'accel': 5, 'stab': 5, 'nitro': 5, 'earn': 5},
      'colors': {'primary': '#ff0000'},
      'shape': {'wb': [0.2, 0.75], 'wr': 0.09, 'ride': 0.05, 'belt': 0.2, 'roof': 0.36, 'rx0': 0.3, 'rx1': 0.6, 'ax': 0.1, 'fx': 0.7, 'hood': 0.2, 'nose': 0.1, 'tail': 0.2, 'wing': 0},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null); // allow real loopback sockets
  late FakePages pages;
  late LocalStore store;

  setUp(() async {
    pages = FakePages();
    await pages.start();
    final dir = await Directory.systemTemp.createTemp('trl_sync');
    store = await LocalStore.forTest(dir.path);
  });
  tearDown(() async {
    await pages.server.close(force: true);
    await Hive.close();
  });

  ContentSync sync({int app = 1}) => ContentSync(store, baseUrl: pages.base, appVersionCode: app);

  test('downloads changed files, verifies hashes, commits to Hive and loads them', () async {
    pages.publish({'vehicles': vehicleFile([v('c_live1'), v('c_live2')])}, version: 50);
    final r = await sync().refresh();
    expect(r.ok, isTrue, reason: r.error);
    expect(r.updated, isTrue);
    expect(r.changedFiles, ['vehicles']);
    final db = await ContentRepository(store).loadLocal();
    expect(db.vehicle('c_live1'), isNotNull);
    expect(db.catalogVersion, 50);
  });

  test('second fetch is a conditional request (ETag) and does not re-download files', () async {
    pages.publish({'vehicles': vehicleFile([v('c_live1')])}, version: 50);
    await sync().refresh();
    pages.hits.clear();
    final r = await sync().refresh();
    expect(r.notModified, isTrue);
    expect(pages.hits, ['catalog.json']);
  });

  test('a file whose hash does not match is rejected and nothing is committed', () async {
    pages.publish({'vehicles': vehicleFile([v('c_evil')])}, version: 60, badHash: true);
    final r = await sync().refresh();
    expect(r.ok, isFalse);
    expect(r.error, contains('hash mismatch'));
    expect(store.content.get('catalog'), isNull);
    expect(store.content.get('file:vehicles'), isNull);
  });

  test('a tampered catalog (checksum file disagrees) is rejected', () async {
    pages.publish({'vehicles': vehicleFile([v('c_live1')])}, version: 61);
    pages.files['catalog.json.sha256'] = utf8.encode('a' * 64);
    final r = await sync().refresh();
    expect(r.error, contains('checksum'));
  });

  test('unsafe paths, bad schema, wrong types and too-new content are refused', () async {
    for (final bad in [
      {'schema': 1, 'version': 70, 'files': {'vehicles': {'path': '../secret.json', 'version': 1, 'sha256': 'a' * 64}}},
      {'schema': 1, 'version': 70, 'files': {'vehicles': {'path': 'run.sh', 'version': 1, 'sha256': 'a' * 64}}},
      {'schema': 1, 'version': 70, 'files': {'vehicles': {'path': 'http://evil/x.json', 'version': 1, 'sha256': 'a' * 64}}},
      {'schema': 99, 'version': 70, 'files': {'vehicles': {'path': 'vehicles.json', 'version': 1, 'sha256': 'a' * 64}}},
      {'schema': 1, 'version': 70, 'files': {}},
      {'schema': 1, 'version': 'x', 'files': {'vehicles': {'path': 'vehicles.json', 'version': 1, 'sha256': 'a' * 64}}},
      {'schema': 1, 'version': 70, 'minAppVersion': 999, 'files': {'vehicles': {'path': 'vehicles.json', 'version': 1, 'sha256': 'a' * 64}}},
      {'schema': 1, 'version': 70, 'files': {'vehicles': {'path': 'vehicles.json', 'version': 1, 'sha256': 'short'}}},
    ]) {
      pages.put('catalog.json', bad);
      pages.files.remove('catalog.json.sha256');
      final r = await sync().refresh();
      expect(r.ok, isFalse, reason: jsonEncode(bad));
    }
    expect(store.content.get('catalog'), isNull);
  });

  test('never rolls back to an older catalog version', () async {
    pages.publish({'vehicles': vehicleFile([v('c_new')])}, version: 80);
    await sync().refresh();
    pages.publish({'vehicles': vehicleFile([v('c_old')])}, version: 79);
    pages.files['catalog.json'] = pages.files['catalog.json']!;
    final r = await sync().refresh();
    expect(r.updated, isFalse);
    final db = await ContentRepository(store).loadLocal();
    expect(db.vehicle('c_new'), isNotNull);
    expect(db.vehicle('c_old'), isNull);
  });

  test('kill switch and feature flags travel with the catalog', () async {
    pages.publish({'vehicles': vehicleFile([v('c_live1'), v('c_bad')])}, version: 90, extra: {
      'killSwitch': {'features': ['ads', 'tournament'], 'items': ['c_bad']}
    });
    await sync().refresh();
    final db = await ContentRepository(store).loadLocal();
    expect(db.featureOn('ads'), isFalse);
    expect(db.featureOn('tournament'), isFalse);
    expect(db.featureOn('shop'), isTrue);
    expect(db.itemAvailable(db.vehicle('c_bad')!), isFalse);
    expect(db.itemAvailable(db.vehicle('c_live1')!), isTrue);
  });

  test('invalid items inside a file are skipped without breaking the rest', () async {
    final broken = {'id': 'c_broken', 'type': 'vehicle', 'kind': 'spaceship'};
    pages.publish({'vehicles': vehicleFile([v('c_ok'), broken])}, version: 95);
    final r = await sync().refresh();
    expect(r.ok, isTrue, reason: r.error);
    final db = await ContentRepository(store).loadLocal();
    expect(db.vehicle('c_ok'), isNotNull);
    expect(db.vehicle('c_broken'), isNull);
  });

  test('network failure and server errors are reported, never thrown', () async {
    await pages.server.close(force: true);
    final r = await ContentSync(store, baseUrl: 'http://127.0.0.1:1/content', timeout: const Duration(seconds: 2)).refresh();
    expect(r.ok, isFalse);
    final pages2 = FakePages();
    await pages2.start();
    addTearDown(() => pages2.server.close(force: true));
    final r2 = await ContentSync(store, baseUrl: pages2.base).refresh();
    expect(r2.error, contains('404'));
  });

  test('the repository catalog validator accepts the real seed catalog', () {
    final cat = jsonDecode(File('content/catalog.json').readAsStringSync()) as Map<String, dynamic>;
    expect(ContentSync.validateCatalog(cat), isNull);
  });
}
