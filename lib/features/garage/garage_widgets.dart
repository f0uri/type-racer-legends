import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/models/content_models.dart';
import '../content/content_db.dart';
import 'look.dart';
import 'vehicle_painter.dart';

const slotLabels = {
  'paint': ('🎨', 'الطلاء'),
  'rims': ('🛞', 'الإطارات'),
  'neon': ('💡', 'نيون'),
  'exhaust': ('💨', 'العادم'),
  'nitroFlame': ('🔥', 'لهب النيترو'),
  'sticker1': ('⭐', 'ملصق 1'),
  'sticker2': ('✨', 'ملصق 2'),
  'plate': ('🔢', 'اللوحة'),
  'horn': ('📯', 'البوق'),
  'celebration': ('🎉', 'الاحتفال'),
};

const celebrationIcons = {'confetti': '🎊', 'fireworks': '🎆', 'flags': '🏁', 'lightning': '⚡', 'smoke': '💨', 'donut': '🍩', 'wheelie': '🏍️'};

String rarityLabel(String r) => r == 'legendary' ? 'أسطوري' : (r == 'rare' ? 'نادر' : 'شائع');

class RarityBadge extends StatelessWidget {
  const RarityBadge(this.rarity, {super.key});
  final String rarity;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: C.rarity(rarity).withValues(alpha: 0.18), border: Border.all(color: C.rarity(rarity)), borderRadius: BorderRadius.circular(10)),
        child: Text(rarityLabel(rarity), style: TextStyle(color: C.rarity(rarity), fontSize: 11, fontWeight: FontWeight.w800)),
      );
}

/// Static picture of a vehicle with the given look (used inside tiles).
class MiniVehicle extends StatelessWidget {
  const MiniVehicle({super.key, required this.look, this.size = 74});
  final Look look;
  final double size;
  @override
  Widget build(BuildContext context) => RepaintBoundary(child: CustomPaint(size: Size(size, size * 0.52), painter: _MiniPainter(look, size)));
}

class _MiniPainter extends CustomPainter {
  final Look look;
  final double L;
  _MiniPainter(this.look, this.L);
  @override
  void paint(Canvas canvas, Size size) {
    final bike = look.vehicle.isBike;
    final len = L * (bike ? 0.72 : 0.92);
    canvas.save();
    canvas.translate((size.width - len) / 2, size.height * 0.98);
    VehiclePainter.paint(canvas, look, len, t: 0.6, showRider: bike, underglow: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniPainter old) => old.look != look;
}

/// Generic selectable tile used for skins / outfits.
class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.preview, required this.name, required this.rarity, this.equipped = false, this.selected = false, this.locked = false, this.isNew = false, this.priceLabel, this.onTap});
  final Widget preview;
  final String name;
  final String rarity;
  final bool equipped, selected, locked, isNew;
  final String? priceLabel;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 98,
          margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected ? C.surface2 : C.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? C.cyan : C.rarity(rarity).withValues(alpha: 0.55), width: selected ? 2.2 : 1.2),
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Center(child: Opacity(opacity: locked ? 0.5 : 1, child: preview))),
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            SizedBox(
              height: 16,
              child: equipped
                  ? const Text('✓ مجهّز', style: TextStyle(color: C.green, fontSize: 10, fontWeight: FontWeight.w900))
                  : (locked ? const Icon(Icons.lock_rounded, size: 13, color: Colors.white38) : Text(priceLabel ?? 'مملوك', style: const TextStyle(color: C.gold, fontSize: 10, fontWeight: FontWeight.w800))),
            ),
            ]),
            if (isNew) const Positioned(top: -4, left: -4, child: NewBadge()),
          ]),
        ),
      );
}

/// Simple previews for non-visual-on-vehicle slots.
class SkinGlyph extends StatelessWidget {
  const SkinGlyph({super.key, required this.skin, required this.look});
  final Skin skin;
  final Look look;
  @override
  Widget build(BuildContext context) {
    switch (skin.slot) {
      case 'sticker':
        return CustomPaint(size: const Size(46, 46), painter: _StickerPainter(skin));
      case 'horn':
        return const Icon(Icons.volume_up_rounded, size: 34, color: C.cyan);
      case 'celebration':
        return Text(celebrationIcons[skin.params['type']] ?? '🎉', style: const TextStyle(fontSize: 32));
      case 'exhaust':
        return Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('💨', style: TextStyle(fontSize: 26)),
          Container(width: 34, height: 6, decoration: BoxDecoration(color: hexColor(skin.params['color'] as String?, C.textDim), borderRadius: BorderRadius.circular(3))),
        ]);
      case 'nitroFlame':
        final cols = hexList(skin.params['colors']);
        return Container(
          width: 52,
          height: 30,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: LinearGradient(colors: cols.length >= 2 ? cols : [C.cyan, C.magenta])),
          alignment: Alignment.center,
          child: const Text('🔥', style: TextStyle(fontSize: 18)),
        );
      case 'plate':
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: hexColor(skin.params['bg'] as String?, Colors.white), borderRadius: BorderRadius.circular(4), border: Border.all(color: hexColor(skin.params['border'] as String?, Colors.black), width: 2)),
          child: Text(look.plateText.isEmpty ? 'TRL' : look.plateText.toUpperCase().substring(0, look.plateText.length.clamp(0, 6)), style: TextStyle(fontFamily: 'FiraMono', fontWeight: FontWeight.w900, fontSize: 13, color: hexColor(skin.params['fg'] as String?, Colors.black))),
        );
      default:
        return const SizedBox();
    }
  }
}

class _StickerPainter extends CustomPainter {
  final Skin skin;
  _StickerPainter(this.skin);
  @override
  void paint(Canvas canvas, Size size) {
    VehiclePainter.drawSticker(canvas, (skin.params['shape'] as String?) ?? 'star', hexColor(skin.params['color'] as String?, C.gold), size.center(Offset.zero), size.width * 0.42, number: (skin.params['number'] as num?)?.toInt());
  }

  @override
  bool shouldRepaint(covariant _StickerPainter old) => false;
}

String priceText(Price p) => [if (p.coins > 0) '🪙 ${fmtInt(p.coins)}', if (p.gems > 0) '💎 ${fmtInt(p.gems)}'].join(' ');


/// Numbers shown next to each stat (derived from the real gameplay modifiers).
class VehicleMods2 {
  static String effect(String stat, ContentDb db, int base, int up, double perLevel) {
    switch (stat) {
      case 'accel':
        final v = ((base - 3) * 0.006 + up * perLevel * 0.8).clamp(0.0, 0.12) * 100;
        return '+${v.toStringAsFixed(1)}% تقدّم لكل حرف';
      case 'stab':
        final v = ((base - 3) * 0.03 + up * perLevel * 1.5).clamp(0.0, 0.5) * 100;
        return '−${v.toStringAsFixed(0)}% فرملة عند الخطأ';
      case 'nitro':
        final v = 2.2 + base * 0.12 + up * 0.25;
        return '${v.toStringAsFixed(1)}% نيترو لكل حرف';
      default:
        final v = (1 + (base - 3) * 0.02 + up * perLevel * 1.5) * 100;
        return '×${(v / 100).toStringAsFixed(2)} أرباح';
    }
  }
}
