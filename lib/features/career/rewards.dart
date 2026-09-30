import '../../core/util/misc.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';
import '../shop/economy.dart';

/// Generic reward bundle with the keys coins, gems, xp, chest, skin, vehicle, outfit and title (ids for the last five).
class Rewards {
  static bool isEmpty(Map? r) => r == null || r.isEmpty;

  /// Grants the bundle to [p] and returns Arabic description lines (for toasts and dialogs).
  static List<String> grant(PlayerProfile p, ContentDb db, Map<String, dynamic>? r) {
    final lines = <String>[];
    if (r == null) return lines;
    final coins = (r['coins'] as num?)?.toInt() ?? 0;
    final gems = (r['gems'] as num?)?.toInt() ?? 0;
    final xp = (r['xp'] as num?)?.toInt() ?? 0;
    if (coins > 0) {
      p.addCoins(coins);
      lines.add('🪙 +${fmtInt(coins)}');
    }
    if (gems > 0) {
      p.addGems(gems);
      lines.add('💎 +$gems');
    }
    if (xp > 0) {
      p.addXp(xp);
      lines.add('⚡ +$xp خبرة');
    }
    final chest = r['chest'] as String?;
    if (chest != null) {
      Economy.grantChest(p, chest);
      final def = ((db.shop['chests'] as List?) ?? const []).cast<Map>().where((c) => c['id'] == chest).firstOrNull;
      lines.add('🎁 ${def == null ? 'صندوق' : loc(def['name'])}');
    }
    final skin = r['skin'] as String?;
    if (skin != null) {
      if (p.ownsSkin(skin)) {
        p.addCoins(500);
        lines.add('🪙 +500 (بدل عنصر مكرر)');
      } else {
        p.grantSkin(skin);
        final s = db.skin(skin);
        lines.add('🎨 ${s == null ? skin : loc(s.name)}');
      }
    }
    final vehicle = r['vehicle'] as String?;
    if (vehicle != null && !p.ownsVehicle(vehicle)) {
      p.grantVehicle(vehicle);
      final v = db.vehicle(vehicle);
      lines.add('🚗 ${v == null ? vehicle : loc(v.name)}');
    }
    final outfit = r['outfit'] as String?;
    if (outfit != null && !p.ownsOutfit(outfit)) {
      p.grantOutfit(outfit);
      final o = db.outfit(outfit);
      lines.add('🧥 ${o == null ? outfit : loc(o.name)}');
    }
    final title = r['title'] as String?;
    if (title != null) {
      p.grantTitle(title);
      lines.add('🏷️ لقب: ${loc(db.titles[title] ?? title)}');
    }
    return lines;
  }

  /// Short inline preview of a bundle (no granting).
  static String preview(ContentDb db, Map? r) {
    if (r == null || r.isEmpty) return '—';
    final parts = <String>[];
    if ((r['coins'] as num?) != null) parts.add('🪙${fmtCompact(r['coins'] as num)}');
    if ((r['gems'] as num?) != null) parts.add('💎${r['gems']}');
    if ((r['xp'] as num?) != null) parts.add('⚡${r['xp']}');
    if (r['chest'] != null) parts.add('🎁');
    if (r['skin'] != null) parts.add('🎨');
    if (r['vehicle'] != null) parts.add('🚗');
    if (r['outfit'] != null) parts.add('🧥');
    if (r['title'] != null) parts.add('🏷️');
    return parts.join(' ');
  }
}
