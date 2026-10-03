import 'package:flutter/material.dart';
import '../content/content_db.dart';

class RankTier {
  final String id;
  final int rp;
  final String label;
  final Color color;
  final IconData icon;
  const RankTier(this.id, this.rp, this.label, this.color, this.icon);
}

class Ranks {
  static const _labels = {
    'bronze': ('برونزي', Color(0xFFCD7F32), Icons.workspace_premium),
    'silver': ('فضي', Color(0xFFC0C8D6), Icons.military_tech),
    'gold': ('ذهبي', Color(0xFFFFD166), Icons.emoji_events),
    'platinum': ('بلاتيني', Color(0xFF7DF9FF), Icons.verified),
    'diamond': ('ماسي', Color(0xFF6C8CFF), Icons.diamond),
    'master': ('أسطوري الماجستير', Color(0xFFB388FF), Icons.auto_awesome),
    'legend': ('أسطورة', Color(0xFFFF2BD6), Icons.local_fire_department),
  };

  static List<RankTier> tiers(ContentDb db) {
    final list = (db.economy['tiers'] as List?) ?? const [];
    final out = <RankTier>[];
    for (final t in list) {
      if (t is! Map) continue;
      final id = t['id'] as String? ?? '';
      final meta = _labels[id];
      if (meta == null) continue;
      out.add(RankTier(id, (t['rp'] as num?)?.toInt() ?? 0, meta.$1, meta.$2, meta.$3));
    }
    if (out.isEmpty) {
      var rp = 0;
      for (final e in const [0, 100, 300, 600, 1000, 1500, 2200].asMap().entries) {
        final id = _labels.keys.elementAt(e.key);
        final m = _labels[id]!;
        out.add(RankTier(id, e.value, m.$1, m.$2, m.$3));
        rp = e.value;
      }
      assert(rp >= 0);
    }
    out.sort((a, b) => a.rp.compareTo(b.rp));
    return out;
  }

  static int tierIndex(ContentDb db, int rp) {
    final t = tiers(db);
    var idx = 0;
    for (var i = 0; i < t.length; i++) {
      if (rp >= t[i].rp) idx = i;
    }
    return idx;
  }

  static RankTier tierOf(ContentDb db, int rp) => tiers(db)[tierIndex(db, rp)];

  /// Progress 0..1 to the next tier (1 at the top).
  static double progress(ContentDb db, int rp) {
    final t = tiers(db);
    final i = tierIndex(db, rp);
    if (i >= t.length - 1) return 1;
    return ((rp - t[i].rp) / (t[i + 1].rp - t[i].rp)).clamp(0.0, 1.0);
  }

  static int? nextAt(ContentDb db, int rp) {
    final t = tiers(db);
    final i = tierIndex(db, rp);
    return i >= t.length - 1 ? null : t[i + 1].rp;
  }
}
