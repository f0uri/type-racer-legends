import '../../core/util/countries.dart';
import '../../data/models/profile.dart';
import '../career/rank.dart';
import '../content/content_db.dart';
import '../race/engine/race_models.dart';
import '../race/race_builder.dart';
import '../../core/util/misc.dart';
import 'share_card.dart';

/// Builds the data behind the shareable player card and the post-race card.
class CardBuilder {
  static String titleLabel(ContentDb db, PlayerProfile p) => loc(db.titles[p.title] ?? (p.title == 't_rookie' ? 'مبتدئ' : p.title));

  static CardData player(ContentDb db, PlayerProfile p) {
    final tier = Ranks.tierOf(db, p.rankPoints);
    return CardData(
      name: p.name,
      title: titleLabel(db, p),
      rankLabel: tier.label,
      rankIcon: tier.icon,
      flag: p.country.isEmpty ? '' : flagEmoji(p.country),
      avatar: avatars[p.avatar % avatars.length],
      level: p.level().level,
      look: PlayerRig.from(db, p).look,
      stats: [
        ('أفضل WPM', p.best('best_wpm').round().toString()),
        ('المعدل', p.avgWpm.round().toString()),
        ('السباقات', p.counter('races').toString()),
      ],
    );
  }

  static CardData race(ContentDb db, PlayerProfile p, RaceResult r) {
    final base = player(db, p);
    final hasOpp = r.opponents > 0;
    return CardData(
      name: base.name,
      title: base.title,
      rankLabel: base.rankLabel,
      rankIcon: base.rankIcon,
      flag: base.flag,
      avatar: base.avatar,
      level: base.level,
      look: base.look,
      headline: hasOpp ? (r.won ? 'فوز!' : 'المركز ${r.playerRank}') : 'سباق مكتمل',
      stats: [('WPM', r.wpm.round().toString()), ('الدقة', '${r.accuracy.toStringAsFixed(0)}%'), ('كومبو', r.maxCombo.toString())],
    );
  }
}
