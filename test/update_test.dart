import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/features/update/apk_downloader.dart';
import 'package:type_racer_legends/features/update/update_controller.dart';
import 'package:type_racer_legends/features/update/version_info.dart';

Map<String, dynamic> vj({int code = 200, String url = 'https://github.com/f0uri/type-racer-legends/releases/download/v2/app.apk', int size = 500000, String? sha, bool mandatory = false, int min = 1}) => {
      'versionCode': code,
      'versionName': '2.0.0',
      'apkUrl': url,
      'size': size,
      'sha256': sha ?? 'a' * 64,
      'notes': {'ar': 'تحسينات', 'en': 'Improvements'},
      'minSupportedVersion': min,
      'mandatory': mandatory,
      'publishedAt': '2026-09-30T10:00:00Z',
    };

void main() {
  setUpAll(() => HttpOverrides.global = null);

  group('VersionInfo', () {
    test('parses a valid version.json', () {
      final v = VersionInfo.tryParse(vj())!;
      expect(v.versionCode, 200);
      expect(v.notesAr, 'تحسينات');
      expect(v.sizeLabel, '488 KB');
      expect(v.publishedAt, isNotNull);
    });

    test('rejects malformed data, non-https urls, untrusted hosts and bad hashes', () {
      expect(VersionInfo.tryParse(null), isNull);
      expect(VersionInfo.tryParse('x'), isNull);
      expect(VersionInfo.tryParse(vj(url: 'http://github.com/a.apk')), isNull);
      expect(VersionInfo.tryParse(vj(url: 'https://evil.example.com/a.apk')), isNull);
      expect(VersionInfo.tryParse(vj(url: 'https://github.com.evil.com/a.apk')), isNull);
      expect(VersionInfo.tryParse(vj(sha: 'xyz')), isNull);
      expect(VersionInfo.tryParse(vj(code: 0)), isNull);
      expect(VersionInfo.tryParse(vj(size: 5)), isNull);
      expect(VersionInfo.tryParse(vj(url: 'https://objects.githubusercontent.com/x.apk')), isNotNull);
      expect(VersionInfo.tryParse(vj(url: 'https://f0uri.github.io/x.apk')), isNotNull);
    });

    test('mandatory when flagged, below minSupportedVersion, or below the remote minimum', () {
      final v = VersionInfo.tryParse(vj(min: 150))!;
      expect(v.isMandatoryFor(149), isTrue);
      expect(v.isMandatoryFor(150), isFalse);
      expect(v.isMandatoryFor(150, remoteMin: 160), isTrue);
      expect(VersionInfo.tryParse(vj(mandatory: true))!.isMandatoryFor(199), isTrue);
    });
  });

  group('UpdateDecision', () {
    test('only newer versions are offered; mandatory only when required', () {
      final info = VersionInfo.tryParse(vj(code: 200, min: 120))!;
      expect(UpdateDecision.decide(currentCode: 200, info: info).available, isFalse);
      expect(UpdateDecision.decide(currentCode: 250, info: info).available, isFalse);
      final optional = UpdateDecision.decide(currentCode: 150, info: info);
      expect(optional.available, isTrue);
      expect(optional.mandatory, isFalse);
      final forced = UpdateDecision.decide(currentCode: 100, info: info);
      expect(forced.mandatory, isTrue);
      expect(UpdateDecision.decide(currentCode: 100, info: null).available, isFalse);
    });
  });

  group('ApkDownloader', () {
    late HttpServer server;
    late Directory dir;
    late List<int> apk;
    var rangeRequests = <String>[];
    var ignoreRange = false;
    var slowMs = 0;
    var failAfterBytes = -1;

    VersionInfo info({String? sha}) => VersionInfo.tryParse(vj(url: 'https://github.com/x/app.apk', size: apk.length, sha: sha ?? sha256.convert(apk).toString()))!.let((v) => VersionInfo(versionCode: v.versionCode, versionName: v.versionName, apkUrl: 'http://127.0.0.1:${server.port}/app.apk', size: v.size, sha256: v.sha256, notes: v.notes, minSupportedVersion: 1, mandatory: false));

    setUp(() async {
      final r = Random(7);
      apk = List.generate(600000, (_) => r.nextInt(256));
      dir = await Directory.systemTemp.createTemp('trl_apk');
      rangeRequests = [];
      ignoreRange = false;
      slowMs = 0;
      failAfterBytes = -1;
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        final range = req.headers.value('range');
        if (range != null) rangeRequests.add(range);
        var start = 0;
        if (range != null && !ignoreRange) {
          start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          if (start >= apk.length) {
            req.response.statusCode = 416;
            await req.response.close();
            return;
          }
          req.response.statusCode = 206;
          req.response.headers.set('content-range', 'bytes $start-${apk.length - 1}/${apk.length}');
        }
        final body = apk.sublist(start);
        req.response.contentLength = body.length;
        var sent = 0;
        try {
          for (var i = 0; i < body.length; i += 50000) {
            final end = min(i + 50000, body.length);
            req.response.add(body.sublist(i, end));
            sent += end - i;
            await req.response.flush();
            if (slowMs > 0) await Future<void>.delayed(Duration(milliseconds: slowMs));
            if (failAfterBytes >= 0 && sent >= failAfterBytes) {
              final sock = await req.response.detachSocket(writeHeaders: false);
              sock.destroy();
              return;
            }
          }
          await req.response.close();
        } catch (_) {}
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    test('downloads, reports progress and verifies the SHA-256', () async {
      final d = ApkDownloader(stall: const Duration(seconds: 4));
      final progress = <int>[];
      final f = await d.download(info(), dir, onProgress: (got, total) => progress.add(got));
      expect(await f.length(), apk.length);
      expect(progress.last, apk.length);
      expect(progress.length, greaterThanOrEqualTo(2));
      expect(await ApkDownloader.sha256Of(f), sha256.convert(apk).toString());
      expect(await d.partFile(dir, info()).exists(), isFalse);
    });

    test('a corrupted download is deleted and reported', () async {
      final d = ApkDownloader(stall: const Duration(seconds: 4));
      await expectLater(d.download(info(sha: 'b' * 64), dir), throwsA(isA<HashMismatch>()));
      expect(await d.partFile(dir, info()).exists(), isFalse);
      expect(await d.targetFile(dir, info()).exists(), isFalse);
    });

    test('cancel keeps the partial file, and the next attempt resumes with a Range request', () async {
      slowMs = 40;
      final d = ApkDownloader(stall: const Duration(seconds: 4));
      final cancel = CancelToken();
      var got = 0;
      await expectLater(
        d.download(info(), dir, cancel: cancel, onProgress: (g, t) {
          got = g;
          if (g > 150000) cancel.cancel();
        }),
        throwsA(isA<DownloadCancelled>()),
      );
      final partial = await d.partFile(dir, info()).length();
      expect(partial, inInclusiveRange(1, apk.length - 1));
      expect(got, greaterThan(150000));
      slowMs = 0;
      final f = await d.download(info(), dir);
      expect(rangeRequests.last, 'bytes=$partial-');
      expect(await ApkDownloader.sha256Of(f), sha256.convert(apk).toString());
    });

    test('a dropped connection can be resumed', () async {
      failAfterBytes = 200000;
      final d = ApkDownloader(stall: const Duration(seconds: 4));
      await expectLater(d.download(info(), dir), throwsA(isA<DownloadFailed>()));
      final partial = await d.partFile(dir, info()).length();
      expect(partial, greaterThan(0));
      failAfterBytes = -1;
      final f = await d.download(info(), dir);
      expect(await f.length(), apk.length);
      expect(rangeRequests, isNotEmpty);
    });

    test('a server that ignores Range makes the download restart cleanly', () async {
      failAfterBytes = 120000;
      final d = ApkDownloader(stall: const Duration(seconds: 4));
      await expectLater(d.download(info(), dir), throwsA(isA<DownloadFailed>()));
      failAfterBytes = -1;
      ignoreRange = true;
      final f = await d.download(info(), dir);
      expect(await ApkDownloader.sha256Of(f), sha256.convert(apk).toString());
    });

    test('an already downloaded, intact APK is reused without hitting the network', () async {
      final d = ApkDownloader(stall: const Duration(seconds: 4));
      await d.download(info(), dir);
      rangeRequests.clear();
      var requests = 0;
      await server.close(force: true);
      server = await HttpServer.bind('127.0.0.1', 0)
        ..listen((r) {
          requests++;
          r.response.close();
        });
      final v = info();
      final again = await d.download(VersionInfo(versionCode: v.versionCode, versionName: v.versionName, apkUrl: 'http://127.0.0.1:${server.port}/app.apk', size: v.size, sha256: v.sha256, notes: v.notes, minSupportedVersion: 1, mandatory: false), dir);
      expect(await again.length(), apk.length);
      expect(requests, 0);
    });

    test('http errors surface as DownloadFailed', () async {
      await server.close(force: true);
      server = await HttpServer.bind('127.0.0.1', 0)
        ..listen((r) {
          r.response.statusCode = 404;
          r.response.close();
        });
      final v = info();
      await expectLater(ApkDownloader().download(VersionInfo(versionCode: 1, versionName: 'x', apkUrl: 'http://127.0.0.1:${server.port}/a.apk', size: v.size, sha256: v.sha256, notes: const {}, minSupportedVersion: 1, mandatory: false), dir), throwsA(isA<DownloadFailed>()));
    });

    test('clean removes stale downloads but keeps the current one', () async {
      final d = ApkDownloader(stall: const Duration(seconds: 4));
      await File('${dir.path}/TypeRacerLegends-100.apk').writeAsString('old');
      await File('${dir.path}/TypeRacerLegends-150.apk.part').writeAsString('old');
      await File('${dir.path}/TypeRacerLegends-200.apk').writeAsString('keep');
      await d.clean(dir, keepCode: 200);
      expect(await File('${dir.path}/TypeRacerLegends-100.apk').exists(), isFalse);
      expect(await File('${dir.path}/TypeRacerLegends-150.apk.part').exists(), isFalse);
      expect(await File('${dir.path}/TypeRacerLegends-200.apk').exists(), isTrue);
    });
  });

  test('the release script produces a version.json this parser accepts', () async {
    final tmp = await Directory.systemTemp.createTemp('trl_ver');
    final apk = File('${tmp.path}/TypeRacerLegends-2.1.0.apk')..writeAsBytesSync(List.filled(200000, 7));
    final r = await Process.run('python3', ['tools/make_version_json.py', apk.path, '2.1.0', '20100', 'f0uri/type-racer-legends', 'v2.1.0'], workingDirectory: Directory.current.path);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final j = jsonDecode(await File('${Directory.current.path}/version.json').readAsString());
    await File('${Directory.current.path}/version.json').delete();
    final v = VersionInfo.tryParse(j)!;
    expect(v.versionCode, 20100);
    expect(v.size, 200000);
    expect(v.sha256, sha256.convert(List.filled(200000, 7)).toString());
    expect(v.apkUrl, startsWith('https://github.com/f0uri/type-racer-legends/releases/download/v2.1.0/'));
    await tmp.delete(recursive: true);
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
