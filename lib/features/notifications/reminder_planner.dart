import '../../core/providers.dart';
import '../../core/util/dates.dart';
import '../../core/util/misc.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';

class Reminder {
  final int id;
  final DateTime at;
  final String title, body;
  const Reminder(this.id, this.at, this.title, this.body);
}

/// Decides which local notifications should be scheduled (pure: easy to test, no plugin calls).
class ReminderPlanner {
  static const streakId = 100;
  static const streakHour = 22; // the streak day ends at midnight: remind two hours before
  static const eventHour = 17;
  static const horizonDays = 14;

  static List<Reminder> plan({required ContentDb db, required PlayerProfile p, required GameSettings s, required DateTime now}) {
    final out = <Reminder>[];
    if (s.streakReminder && p.streak > 0) {
      final today = DateTime(now.year, now.month, now.day, streakHour);
      final playedToday = p.streakLast == dayKey(now);
      // played today -> the streak is safe today; it will end at the end of tomorrow unless the player returns
      final at = !playedToday && now.isBefore(today) ? today : today.add(const Duration(days: 1));
      final days = playedToday ? p.streak + 1 : p.streak;
      out.add(Reminder(streakId, at, '🔥 سلسلتك في خطر!', 'سلسلة $days يوم ستنتهي بعد ساعتين — افتح اللعبة وحافظ عليها.'));
    }
    if (s.eventNotifs) {
      var i = 0;
      DateTime? at(DateTime day) {
        final t = DateTime(day.year, day.month, day.day, eventHour);
        return t.isAfter(now) && t.isBefore(now.add(const Duration(days: horizonDays))) ? t : null;
      }
      for (final e in db.events) {
        if (!e.enabled || e.startsAt == null || e.endsAt == null || e.endsAt!.isBefore(now)) continue;
        final name = loc(e.name);
        final start = at(e.startsAt!);
        if (start != null) out.add(Reminder(200 + i++, start, '🎉 بدأ حدث $name', 'مهام ومكافآت خاصة بانتظارك — لفترة محدودة!'));
        final last = at(e.endsAt!.subtract(const Duration(days: 1)));
        if (last != null && e.startsAt!.isBefore(last)) out.add(Reminder(200 + i++, last, '⏳ ينتهي حدث $name غداً', 'أكمل مهامك واستلم مكافآتك قبل فوات الأوان.'));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }
}
