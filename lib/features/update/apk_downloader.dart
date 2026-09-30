import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'version_info.dart';

class DownloadCancelled implements Exception {
  @override
  String toString() => 'cancelled';
}

class HashMismatch implements Exception {
  @override
  String toString() => 'sha256 mismatch';
}

class DownloadFailed implements Exception {
  DownloadFailed(this.message);
  final String message;
  @override
  String toString() => message;
}

class CancelToken {
  bool _c = false;
  bool get cancelled => _c;
  void cancel() => _c = true;
}

/// Resumable APK download with cancel, progress and SHA-256 verification.
/// A cancelled or failed download keeps its `.part` file so the next attempt resumes with an HTTP Range request.
class ApkDownloader {
  ApkDownloader({http.Client? client, this.stall = const Duration(seconds: 30)}) : _client = client ?? http.Client();
  final http.Client _client;
  final Duration stall;

  File targetFile(Directory dir, VersionInfo v) => File('${dir.path}/TypeRacerLegends-${v.versionCode}.apk');
  File partFile(Directory dir, VersionInfo v) => File('${targetFile(dir, v).path}.part');

  static Future<String> sha256Of(File f) async => (await sha256.bind(f.openRead()).first).toString();

  /// Returns the verified APK. Throws [DownloadCancelled], [HashMismatch] or [DownloadFailed].
  Future<File> download(VersionInfo v, Directory dir, {void Function(int received, int total)? onProgress, CancelToken? cancel}) async {
    await dir.create(recursive: true);
    final target = targetFile(dir, v);
    final part = partFile(dir, v);
    // already downloaded and intact?
    if (await target.exists()) {
      if (await target.length() == v.size && await sha256Of(target) == v.sha256) {
        onProgress?.call(v.size, v.size);
        return target;
      }
      await target.delete();
    }
    var start = await part.exists() ? await part.length() : 0;
    if (start > v.size) {
      await part.delete();
      start = 0;
    }
    if (start < v.size) {
      final req = http.Request('GET', Uri.parse(v.apkUrl));
      if (start > 0) req.headers['Range'] = 'bytes=$start-';
      final http.StreamedResponse res;
      try {
        res = await _client.send(req).timeout(stall);
      } on TimeoutException {
        throw DownloadFailed('timeout');
      } catch (e) {
        throw DownloadFailed('$e');
      }
      if (res.statusCode == 416) {
        // server says our offset is invalid: start over
        await part.delete();
        return download(v, dir, onProgress: onProgress, cancel: cancel);
      }
      if (res.statusCode != 200 && res.statusCode != 206) throw DownloadFailed('http ${res.statusCode}');
      final resumed = res.statusCode == 206 && start > 0;
      if (!resumed && start > 0) start = 0; // server ignored Range: rewrite from scratch
      final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var received = start;
      try {
        await for (final chunk in res.stream.timeout(stall)) {
          if (cancel?.cancelled == true) {
            await sink.flush();
            await sink.close();
            throw DownloadCancelled();
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, v.size);
        }
        await sink.flush();
        await sink.close();
      } on DownloadCancelled {
        rethrow;
      } on TimeoutException {
        await sink.close();
        throw DownloadFailed('stalled');
      } catch (e) {
        try {
          await sink.close();
        } catch (_) {}
        throw DownloadFailed('$e');
      }
    }
    if (cancel?.cancelled == true) throw DownloadCancelled();
    if (await part.length() != v.size) {
      // wrong length: drop it so a retry starts clean
      await part.delete();
      throw DownloadFailed('size mismatch');
    }
    if (await sha256Of(part) != v.sha256) {
      await part.delete();
      throw HashMismatch();
    }
    await part.rename(target.path);
    onProgress?.call(v.size, v.size);
    return target;
  }

  Future<void> clean(Directory dir, {int keepCode = -1}) async {
    try {
      if (!await dir.exists()) return;
      await for (final f in dir.list()) {
        final n = f.path.split('/').last;
        if (n.startsWith('TypeRacerLegends-') && (n.endsWith('.apk') || n.endsWith('.part')) && !n.contains('-$keepCode.apk')) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  void close() => _client.close();
}
