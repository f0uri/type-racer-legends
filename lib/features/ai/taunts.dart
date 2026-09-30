import 'dart:math';
import '../../core/util/misc.dart';

/// Short in-race chatter for AI opponents (taken from content/ai.json and campaign bosses).
class TauntBook {
  final Map<String, dynamic> byPersona;
  final Map<String, Map<String, dynamic>> bosses;
  TauntBook(this.byPersona, this.bosses);

  String? line(String persona, String event, Random rnd) {
    final p = byPersona[persona] as Map?;
    final l = p?[event] as List?;
    if (l == null || l.isEmpty) return null;
    return loc(l[rnd.nextInt(l.length)]);
  }

  String? bossLine(String bossId, Random rnd) {
    final t = bosses[bossId]?['taunts'] as Map?;
    final l = t?['ar'] as List?;
    if (l == null || l.isEmpty) return null;
    return l[rnd.nextInt(l.length)].toString();
  }

  String? endLine(String persona, bool aiWon, Random rnd) => line(persona, aiWon ? 'win' : 'lose', rnd);
}
