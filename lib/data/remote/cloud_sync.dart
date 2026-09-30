import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../merge/profile_merge.dart';
import '../models/profile.dart';
import 'firebase_boot.dart';

class SyncException implements Exception {
  final String message;
  SyncException(this.message);
  @override
  String toString() => message;
}

/// Cloud persistence via Firestore transactions with CRDT-style merge.
class CloudSync {
  FirebaseFirestore get _fs => FirebaseFirestore.instance;
  String? get uid => FirebaseBoot.available ? FirebaseAuth.instance.currentUser?.uid : null;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _fs.collection('users').doc(uid);

  /// Transactionally merges [local] with the server copy and writes the merged profile.
  /// Returns the merged profile (which the caller must merge again with any newer local edits).
  Future<PlayerProfile> sync(PlayerProfile local) async {
    final id = uid;
    if (id == null) throw SyncException('not-signed-in');
    try {
      PlayerProfile? result;
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(_doc(id));
        PlayerProfile merged;
        var serverRev = 0;
        if (snap.exists && snap.data()?['blob'] is String) {
          final server = PlayerProfile.fromJson(snap.data()!['blob'] as String);
          serverRev = (snap.data()!['rev'] as num?)?.toInt() ?? 0;
          merged = ProfileMerger.merge(local, server);
        } else {
          merged = local.clone();
        }
        merged.uid = id;
        final payload = <String, dynamic>{
          ...ProfileMerger.summary(merged),
          'blob': jsonEncode(merged.d),
          'rev': serverRev + 1,
          'schema': merged.d['v'],
          'updatedAt': FieldValue.serverTimestamp(),
        };
        tx.set(_doc(id), payload);
        result = merged;
      });
      return result!;
    } on FirebaseException catch (e) {
      throw SyncException(e.code);
    }
  }

  Future<PlayerProfile?> fetch() async {
    final id = uid;
    if (id == null) return null;
    try {
      final snap = await _doc(id).get();
      final b = snap.data()?['blob'];
      return b is String ? PlayerProfile.fromJson(b) : null;
    } on FirebaseException catch (e) {
      throw SyncException(e.code);
    }
  }

  /// Latest cloud backups (written by the onUserWrite Cloud Function).
  Future<List<PlayerProfile>> backups() async {
    final id = uid;
    if (id == null) return [];
    final q = await _doc(id).collection('backups').orderBy('at', descending: true).limit(3).get();
    return q.docs.map((d) => d.data()['blob']).whereType<String>().map(PlayerProfile.fromJson).toList();
  }

  Future<T?> callFn<T>(String name, Map<String, dynamic> data) async {
    if (!FirebaseBoot.available) return null;
    try {
      final r = await FirebaseFunctions.instance.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 20))).call<dynamic>(data);
      return r.data as T?;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('fn $name failed: ${e.code} ${e.message}');
      rethrow;
    }
  }
}
