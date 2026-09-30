import 'dart:ui';
import '../../data/models/content_models.dart';
import '../content/content_db.dart';

Color hexColor(String? h, [Color fallback = const Color(0xFFFFFFFF)]) {
  if (h == null || h.isEmpty) return fallback;
  var s = h.replaceAll('#', '');
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return fallback;
  final v = int.tryParse(s, radix: 16);
  return v == null ? fallback : Color(v);
}

List<Color> hexList(dynamic l) => l is List ? l.map((e) => hexColor(e.toString())).toList() : <Color>[];

class StickerLook {
  final String shape;
  final Color color;
  final int? number;
  const StickerLook(this.shape, this.color, this.number);
}

class OutfitLook {
  final Color helmet, suit, suit2, visor;
  final String style;
  const OutfitLook(this.helmet, this.suit, this.suit2, this.visor, this.style);
  static const fallback = OutfitLook(Color(0xFFE5383B), Color(0xFF2B2D42), Color(0xFFE5383B), Color(0xFF111827), 'full');
}

/// Fully resolved, renderable appearance of a vehicle (colors, pattern, rims, effects...).
class Look {
  final Vehicle vehicle;
  final Color primary, secondary, accent;
  final String pattern;
  final List<Color> patternColors;
  final bool metallic, shimmer;
  final String rimStyle;
  final Color rimColor;
  final Color? rimGlow;
  final Color? neon;
  final bool neonPulse, neonRainbow;
  final String exhaustEffect;
  final Color exhaustColor;
  final List<Color> flameColors;
  final String flameShape;
  final List<StickerLook> stickers;
  final Color plateBg, plateFg, plateBorder;
  final bool plateGlow;
  final String plateText;
  final OutfitLook outfit;
  final String hornId, celebration;
  final List<Color> celebrationColors;
  final String? imageUrl;

  const Look({
    required this.vehicle,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.pattern,
    required this.patternColors,
    this.metallic = false,
    this.shimmer = false,
    this.rimStyle = 'spoke5',
    this.rimColor = const Color(0xFFDFE3E8),
    this.rimGlow,
    this.neon,
    this.neonPulse = false,
    this.neonRainbow = false,
    this.exhaustEffect = 'smoke',
    this.exhaustColor = const Color(0xFFC9CED6),
    this.flameColors = const [Color(0xFF7DF9FF), Color(0xFF2A6BFF), Color(0xFFFFFFFF)],
    this.flameShape = 'cone',
    this.stickers = const [],
    this.plateBg = const Color(0xFFF8F9FA),
    this.plateFg = const Color(0xFF111111),
    this.plateBorder = const Color(0xFF111111),
    this.plateGlow = false,
    this.plateText = '',
    this.outfit = OutfitLook.fallback,
    this.hornId = 'h_classic',
    this.celebration = 'confetti',
    this.celebrationColors = const [Color(0xFFFF006E), Color(0xFFFFBE0B), Color(0xFF3A86FF)],
    this.imageUrl,
  });

  /// Builds a look from a loadout map (slot -> skin id) resolved against the content database.
  factory Look.resolve(ContentDb db, Vehicle v, Map<String, dynamic> lo, {String? outfitId, String plateName = ''}) {
    final base = v.colors;
    var primary = hexColor(lo['color'] as String? ?? base['primary'] as String?, const Color(0xFFE5383B));
    final secondary = hexColor(base['secondary'] as String?, const Color(0xFF222222));
    final accent = hexColor(base['accent'] as String?, const Color(0xFFFFD166));
    var pattern = 'solid';
    var pcols = <Color>[primary];
    var metallic = false, shimmer = false;
    Skin? sk(String slot) {
      final id = lo[slot] as String?;
      if (id == null) return null;
      final s = db.skin(id);
      return (s != null && s.slot == slot) ? s : null;
    }

    final paint = sk('paint');
    if (paint != null) {
      pattern = (paint.params['pattern'] as String?) ?? 'solid';
      pcols = hexList(paint.params['colors']);
      if (pcols.isEmpty) pcols = [primary];
      primary = pcols.first;
      metallic = paint.params['metallic'] == true;
      shimmer = paint.params['shimmer'] == true;
    }
    final rims = sk('rims');
    final neon = sk('neon');
    final exh = sk('exhaust');
    final fl = sk('nitroFlame');
    final plate = sk('plate');
    final horn = sk('horn');
    final cel = sk('celebration');
    final stickers = <StickerLook>[];
    for (final k in ['sticker1', 'sticker2']) {
      final sid = lo[k] as String?;
      final s = sid == null ? null : db.skin(sid);
      if (s != null && s.slot == 'sticker') stickers.add(StickerLook((s.params['shape'] as String?) ?? 'star', hexColor(s.params['color'] as String?), (s.params['number'] as num?)?.toInt()));
    }
    final o = db.outfit(outfitId ?? 'o_default');
    final op = o?.params ?? const {};
    return Look(
      vehicle: v,
      primary: primary,
      secondary: secondary,
      accent: accent,
      pattern: pattern,
      patternColors: pcols,
      metallic: metallic,
      shimmer: shimmer,
      rimStyle: (rims?.params['style'] as String?) ?? 'spoke5',
      rimColor: hexColor(rims?.params['color'] as String?, const Color(0xFFDFE3E8)),
      rimGlow: rims?.params['glow'] == null ? null : hexColor(rims!.params['glow'] as String?),
      neon: neon == null ? null : hexColor(neon.params['color'] as String?),
      neonPulse: neon?.params['pulse'] == true,
      neonRainbow: neon?.params['rainbow'] == true,
      exhaustEffect: (exh?.params['effect'] as String?) ?? 'smoke',
      exhaustColor: hexColor(exh?.params['color'] as String?, const Color(0xFFC9CED6)),
      flameColors: fl == null ? const [Color(0xFF7DF9FF), Color(0xFF2A6BFF), Color(0xFFFFFFFF)] : hexList(fl.params['colors']),
      flameShape: (fl?.params['shape'] as String?) ?? 'cone',
      stickers: stickers,
      plateBg: hexColor(plate?.params['bg'] as String?, const Color(0xFFF8F9FA)),
      plateFg: hexColor(plate?.params['fg'] as String?, const Color(0xFF111111)),
      plateBorder: hexColor(plate?.params['border'] as String?, const Color(0xFF111111)),
      plateGlow: plate?.params['glow'] == true,
      plateText: plateName,
      outfit: o == null ? OutfitLook.fallback : OutfitLook(hexColor(op['helmet'] as String?), hexColor(op['suit'] as String?), hexColor(op['suit2'] as String?), hexColor(op['visor'] as String?), (op['style'] as String?) ?? 'full'),
      hornId: horn?.id ?? 'h_classic',
      celebration: (cel?.params['type'] as String?) ?? 'confetti',
      celebrationColors: cel == null ? const [Color(0xFFFF006E), Color(0xFFFFBE0B), Color(0xFF3A86FF)] : hexList(cel.params['colors']),
      imageUrl: v.imageUrl,
    );
  }

  /// Plain look for AI racers with a given paint.
  factory Look.forAi(ContentDb db, String vehicleId, String paintId) {
    final v = db.vehicle(vehicleId) ?? db.starterCar;
    return Look.resolve(db, v, {'paint': paintId}, outfitId: null);
  }
}
