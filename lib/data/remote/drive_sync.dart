import 'dart:convert';

import 'package:http/http.dart' as http;

/// A file inside the player's hidden Google Drive app folder.
class DriveFileRef {
  final String id;
  final DateTime? modified;

  /// The save revision stored in the file's private `appProperties` (null for older files).
  /// It is what tells a reinstall that the cloud copy is further along than the fresh local one.
  final int? rev;
  const DriveFileRef(this.id, this.modified, [this.rev]);
}

/// The outcome of a push. [remoteAhead] means the cloud copy carries a higher revision than the
/// local one, so the caller must pull-merge before writing instead of overwriting fresh data.
class DrivePushResult {
  final bool remoteAhead;
  const DrivePushResult({this.remoteAhead = false});
  static const ok = DrivePushResult();
  static const ahead = DrivePushResult(remoteAhead: true);
}

class DriveException implements Exception {
  final String message;
  const DriveException(this.message);
  @override
  String toString() => 'DriveException($message)';
}

/// The access token has expired or does not carry the Drive scope: the caller must
/// re-authorize (silently first, interactively if needed) and retry.
class DriveAuthException extends DriveException {
  const DriveAuthException() : super('auth');
}

/// Cloud saves with no server of your own.
///
/// The save lives in the player's own Google Drive, inside the hidden `appDataFolder` space: it
/// is invisible in the normal Drive UI, it is deleted with the account, and it costs nothing to
/// run. The same three calls every Drive sync needs: find the file, download it, upload it.
///
/// Scope: `drive.appdata` only — the game can never read any other file in the player's Drive.
class DriveSync {
  DriveSync([http.Client? client]) : _http = client ?? http.Client();

  final http.Client _http;

  /// The only permission the game ever asks for. It grants access to files this app created,
  /// and nothing else in the player's Drive.
  static const scope = 'https://www.googleapis.com/auth/drive.appdata';

  /// Single save file per player (progress, cars, wallet, settings — everything).
  static const fileName = 'type-racer-legends-save.json';

  static const _files = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  Map<String, String> _auth(String token) => {'Authorization': 'Bearer $token'};

  /// The existing save file, or null when the player has never synced.
  Future<DriveFileRef?> find(String token) async {
    // `Uri.replace` encodes the query safely (the `q` value contains spaces and quotes).
    final uri = Uri.parse(_files).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'fields': 'files(id,name,modifiedTime,appProperties)',
      'q': "name = '$fileName' and trashed = false",
    });
    final r = await _http.get(uri, headers: _auth(token));
    if (r.statusCode == 401 || r.statusCode == 403) throw const DriveAuthException();
    if (r.statusCode != 200) throw DriveException('list ${r.statusCode}');
    final body = jsonDecode(r.body);
    final files = body is Map ? (body['files'] as List?) : null;
    if (files == null || files.isEmpty) return null;
    final f = (files.first as Map).cast<String, dynamic>();
    final id = f['id'];
    if (id is! String || id.isEmpty) return null;
    final props = f['appProperties'];
    final rev = props is Map ? int.tryParse('${props['rev'] ?? ''}') : null;
    return DriveFileRef(id, DateTime.tryParse('${f['modifiedTime'] ?? ''}'), rev);
  }

  /// Downloads the save payload, or null when there is nothing to restore.
  Future<Map<String, dynamic>?> pull(String token) async {
    final ref = await find(token);
    if (ref == null) return null;
    final r = await _http.get(Uri.parse('$_files/${ref.id}?alt=media'), headers: _auth(token));
    if (r.statusCode == 401 || r.statusCode == 403) throw const DriveAuthException();
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) throw DriveException('get ${r.statusCode}');
    if (r.body.isEmpty) return null;
    final decoded = jsonDecode(r.body);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }

  /// Uploads the save payload: creates the file the first time, updates it afterwards.
  ///
  /// If the cloud copy carries a higher revision than [payload], nothing is written and
  /// [DrivePushResult.ahead] is returned — a fresh install that signs in while offline must never
  /// flatten a save that another device already moved forward.
  Future<DrivePushResult> push(String token, Map<String, dynamic> payload) async {
    final localRev = (payload['rev'] as num?)?.toInt() ?? 0;
    final existing = await find(token);
    if (existing != null && (existing.rev ?? -1) > localRev) return DrivePushResult.ahead;
    if (existing == null) {
      await _create(token, payload, localRev);
    } else {
      await _update(token, existing.id, payload, localRev);
    }
    return DrivePushResult.ok;
  }

  /// Removes the cloud save (used when the player deletes their account).
  Future<void> erase(String token) async {
    final ref = await find(token);
    if (ref == null) return;
    final r = await _http.delete(Uri.parse('$_files/${ref.id}'), headers: _auth(token));
    if (r.statusCode == 401 || r.statusCode == 403) throw const DriveAuthException();
    if (r.statusCode != 204 && r.statusCode != 200 && r.statusCode != 404) throw DriveException('delete ${r.statusCode}');
  }

  Future<void> _create(String token, Map<String, dynamic> payload, int rev) async {
    final (bytes, boundary) = _multipart(payload, rev, create: true);
    final r = await _http.post(
      Uri.parse('$_upload?uploadType=multipart'),
      headers: {..._auth(token), 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: bytes,
    );
    if (r.statusCode == 401 || r.statusCode == 403) throw const DriveAuthException();
    if (r.statusCode != 200 && r.statusCode != 201) throw DriveException('create ${r.statusCode}');
  }

  Future<void> _update(String token, String id, Map<String, dynamic> payload, int rev) async {
    final (bytes, boundary) = _multipart(payload, rev, create: false);
    final r = await _http.patch(
      Uri.parse('$_upload/$id?uploadType=multipart'),
      headers: {..._auth(token), 'Content-Type': 'multipart/related; boundary=$boundary'},
      body: bytes,
    );
    if (r.statusCode == 401 || r.statusCode == 403) throw const DriveAuthException();
    if (r.statusCode != 200 && r.statusCode != 201) throw DriveException('update ${r.statusCode}');
  }

  /// Multipart body: metadata part (name, revision, and — when creating — the hidden app folder
  /// parent) followed by the JSON save as the media part.
  (List<int>, String) _multipart(Map<String, dynamic> payload, int rev, {required bool create}) {
    final boundary = 'trl_save_${DateTime.now().millisecondsSinceEpoch}';
    final meta = <String, dynamic>{
      'name': fileName,
      'appProperties': {'app': 'type-racer-legends', 'rev': '$rev'},
      if (create) 'parents': ['appDataFolder'],
    };
    final bytes = <int>[
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode(meta)}\r\n'),
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${jsonEncode(payload)}\r\n'),
      ...utf8.encode('--$boundary--'),
    ];
    return (bytes, boundary);
  }
}
