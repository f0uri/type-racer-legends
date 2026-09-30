import '../../core/util/dates.dart';
import '../../data/models/profile.dart';
import '../content/content_db.dart';

/// Pure rules for optional ads. Nothing here ever shows an ad; it only decides whether one may be offered.
/// Ads are never shown during a race, are optional (rewarded) or rare (interstitial between races),
/// and disappear completely once the player owns "remove ads".
class AdPolicy {
  static bool enabled(ContentDb db, PlayerProfile p) => db.featureOn('ads') && !p.flag('adsRemoved');

  static int rewardedDailyLimit(ContentDb db) => db.econNum('ads', 'rewardedDailyLimit', 6).toInt();
  static int rewardedCoins(ContentDb db) => db.econNum('ads', 'rewardedCoins', 150).toInt();
  static int interstitialEvery(ContentDb db) => db.econNum('ads', 'interstitialEveryNRaces', 3).toInt();
  static int interstitialMinSeconds(ContentDb db) => db.econNum('ads', 'interstitialMinSeconds', 180).toInt();
  static bool interstitialEnabled(ContentDb db) => db.econ('ads')['interstitialEnabled'] != false;

  static String _key([DateTime? now]) => 'ad_${dayKey(now)}';

  static int rewardedToday(PlayerProfile p, [DateTime? now]) => p.counter(_key(now));

  static int rewardedLeft(ContentDb db, PlayerProfile p, [DateTime? now]) => enabled(db, p) ? (rewardedDailyLimit(db) - rewardedToday(p, now)).clamp(0, 999) : 0;

  /// Grants the rewarded-ad bonus; returns the coins granted (0 when the daily limit is used up).
  static int grantRewarded(ContentDb db, PlayerProfile p, {int? coins, DateTime? now}) {
    if (rewardedLeft(db, p, now) <= 0) return 0;
    final c = coins ?? rewardedCoins(db);
    p.addCoins(c);
    p.addCounter(_key(now), 1);
    p.addCounter('ads_watched', 1);
    return c;
  }

  /// Interstitial between two races: remote-configurable frequency + minimum gap, never right after another ad.
  static bool interstitialDue(ContentDb db, PlayerProfile p, {required int racesSinceAd, required int? msSinceLastAd, required bool tutorialOrLesson}) {
    if (!enabled(db, p) || !interstitialEnabled(db) || tutorialOrLesson) return false;
    if (racesSinceAd < interstitialEvery(db)) return false;
    if (msSinceLastAd != null && msSinceLastAd < interstitialMinSeconds(db) * 1000) return false;
    return true;
  }
}
