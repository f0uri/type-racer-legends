import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:type_racer_legends/core/config/app_config.dart';
import 'package:type_racer_legends/data/models/profile.dart';
import 'package:type_racer_legends/data/remote/drive_sync.dart';
import 'package:type_racer_legends/data/remote/progress_sync.dart';

/// The cloud save must behave when every call can go wrong, so the whole Drive layer is tested
/// against a fake HTTP client: no network, no Google account, no plugin.
const _token = 'test-token';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json; charset=utf-8'});

bool _isListRequest(http.BaseRequest r) => r.url.queryParameters.containsKey('spaces');

void main() {
  test('find: queries the app folder only and reads id, time and revision', () async {
    late http.Request seen;
    final sync = DriveSync(MockClient((r) async {
      seen = r;
      return _json({
        'files': [
          {
            'id': 'abc',
            'name': DriveSync.fileName,
            'modifiedTime': '2026-10-04T10:00:00.000Z',
            'appProperties': {'rev': '12'},
          }
        ]
      });
    }));

    final ref = await sync.find(_token);

    expect(ref?.id, 'abc');
    expect(ref?.modified, DateTime.utc(2026, 10, 4, 10));
    expect(ref?.rev, 12);
    expect(seen.url.queryParameters['spaces'], 'appDataFolder');
    expect(seen.url.queryParameters['q'], "name = '${DriveSync.fileName}' and trashed = false");
    expect(seen.headers['Authorization'], 'Bearer $_token');
  });

  test('find: null when the player has never synced', () async {
    final sync = DriveSync(MockClient((_) async => _json({'files': <Object>[]})));
    expect(await sync.find(_token), isNull);
  });

  test('pull: decodes the save file, and returns null when there is none', () async {
    final sync = DriveSync(MockClient((r) async {
      if (_isListRequest(r)) return _json({'files': [{'id': 'abc'}]});
      expect(r.url.path, endsWith('/files/abc'));
      expect(r.url.queryParameters['alt'], 'media');
      return _json({'app': 'type-racer-legends', 'rev': 7});
    }));

    expect((await sync.pull(_token))?['rev'], 7);

    final empty = DriveSync(MockClient((_) async => _json({'files': <Object>[]})));
    expect(await empty.pull(_token), isNull);
  });

  test('push: creates the file inside appDataFolder the first time', () async {
    final methods = <String>[];
    late http.Request create;
    final sync = DriveSync(MockClient((r) async {
      methods.add(r.method);
      if (_isListRequest(r)) return _json({'files': <Object>[]});
      create = r;
      return _json({'id': 'new'});
    }));

    final result = await sync.push(_token, {'app': 'type-racer-legends', 'rev': 1});

    expect(result.remoteAhead, isFalse);
    expect(methods, ['GET', 'POST']);
    expect(create.url.queryParameters['uploadType'], 'multipart');
    expect(create.url.path, endsWith('/upload/drive/v3/files'));
    // metadata part (name, hidden app folder, revision) then the JSON save as the media part
    expect(create.body, contains('"parents":["appDataFolder"]'));
    expect(create.body, contains(DriveSync.fileName));
    expect(create.body, contains('"rev":"1"'));
    expect(create.body, contains('"rev":1'), reason: 'the save itself keeps its revision');
    expect(create.headers['Content-Type'], startsWith('multipart/related; boundary='));
  });

  test('push: updates the existing file in one multipart request', () async {
    final methods = <String>[];
    late http.Request update;
    final sync = DriveSync(MockClient((r) async {
      methods.add(r.method);
      if (_isListRequest(r)) return _json({'files': [{'id': 'abc'}]});
      update = r;
      return _json({'id': 'abc'});
    }));

    final result = await sync.push(_token, {'rev': 2});

    expect(result.remoteAhead, isFalse);
    expect(methods, ['GET', 'PATCH']);
    expect(update.url.path, endsWith('/upload/drive/v3/files/abc'));
    expect(update.url.queryParameters['uploadType'], 'multipart');
    expect(update.body, contains('"rev":"2"'));
    expect(update.body, contains('"rev":2'));
  });

  test('push: refuses to overwrite a save that a further-along device uploaded', () async {
    final methods = <String>[];
    final sync = DriveSync(MockClient((r) async {
      methods.add(r.method);
      return _json({
        'files': [
          {'id': 'abc', 'appProperties': {'rev': '9'}}
        ]
      });
    }));

    final result = await sync.push(_token, {'rev': 2});

    expect(result.remoteAhead, isTrue);
    expect(methods, ['GET'], reason: 'nothing may be written on a conflict');
  });

  test('push: an older cloud file is simply replaced', () async {
    final methods = <String>[];
    final sync = DriveSync(MockClient((r) async {
      methods.add(r.method);
      if (_isListRequest(r)) {
        return _json({
          'files': [
            {'id': 'abc', 'appProperties': {'rev': '3'}}
          ]
        });
      }
      return _json({'id': 'abc'});
    }));

    expect((await sync.push(_token, {'rev': 8})).remoteAhead, isFalse);
    expect(methods, ['GET', 'PATCH']);
  });

  test('expired token: 401 and 403 become DriveAuthException so the caller re-authorizes', () async {
    for (final status in [401, 403]) {
      final sync = DriveSync(MockClient((_) async => _json({'error': 'nope'}, status)));
      await expectLater(sync.find(_token), throwsA(isA<DriveAuthException>()));
      await expectLater(sync.push(_token, {'rev': 1}), throwsA(isA<DriveAuthException>()));
      await expectLater(sync.erase(_token), throwsA(isA<DriveAuthException>()));
    }
  });

  test('other failures are plain DriveExceptions', () async {
    final sync = DriveSync(MockClient((_) async => _json({'error': 'boom'}, 500)));
    await expectLater(sync.find(_token), throwsA(isA<DriveException>()));
  });

  test('erase: deletes the save file, and does nothing when there is none', () async {
    final methods = <String>[];
    final sync = DriveSync(MockClient((r) async {
      methods.add(r.method);
      if (_isListRequest(r)) return _json({'files': [{'id': 'abc'}]});
      expect(r.url.path, endsWith('/files/abc'));
      return http.Response('', 204);
    }));
    await sync.erase(_token);
    expect(methods, ['GET', 'DELETE']);

    final empty = DriveSync(MockClient((_) async => _json({'files': <Object>[]})));
    await empty.erase(_token); // must not throw
  });

  test('the save payload is self-describing and restores the whole profile', () {
    final p = PlayerProfile.fresh('device-1')..addCoins(500);
    final payload = ProgressSyncController.payload(p);

    expect(payload['app'], 'type-racer-legends');
    expect(payload['schema'], AppConfig.profileSchema);
    expect(payload['rev'], p.rev);
    expect(payload['summary'], isA<Map>());
    expect((payload['summary'] as Map)['coins'], 500);
    expect(payload['rev'], isA<int>(), reason: 'the push guard compares revisions as integers');

    // The profile half is the exact JSON the local store uses, so a restore is lossless.
    final restored = PlayerProfile.fromJson(payload['profile'] as String);
    expect(restored.rev, p.rev);
    expect(restored.coins, 500);
    expect(restored.deviceId, 'device-1');
  });
}
