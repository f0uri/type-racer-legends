import '../../data/models/profile.dart';
import 'content_db.dart';

/// "New" badges for items that arrived through live content after the player's first launch.
class NewItems {
  static const baselineFlag = 'newItemsBaseline';

  static Iterable<String> _allIds(ContentDb db) sync* {
    for (final v in db.vehicles) {
      if (db.itemAvailable(v)) yield v.id;
    }
    for (final s in db.skins) {
      if (db.itemAvailable(s)) yield s.id;
    }
    for (final o in db.outfits) {
      if (db.itemAvailable(o)) yield o.id;
    }
  }

  /// First launch: everything that ships with the app counts as already seen.
  static bool ensureBaseline(ContentDb db, PlayerProfile p) {
    if (p.flag(baselineFlag)) return false;
    final seen = p.m('seenItems');
    for (final id in _allIds(db)) {
      seen.putIfAbsent(id, () => 0);
    }
    p.setFlag(baselineFlag);
    return true;
  }

  static Set<String> unseen(ContentDb db, PlayerProfile p) {
    if (!p.flag(baselineFlag)) return const {};
    final seen = p.m('seenItems');
    return {for (final id in _allIds(db)) if (!seen.containsKey(id)) id};
  }

  static bool isNew(PlayerProfile p, String id) => p.flag(baselineFlag) && !p.m('seenItems').containsKey(id);

  static void markSeen(PlayerProfile p, Iterable<String> ids) {
    final seen = p.m('seenItems');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final id in ids) {
      seen.putIfAbsent(id, () => now);
    }
  }
}
