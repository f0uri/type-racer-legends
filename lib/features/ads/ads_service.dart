import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import 'ad_policy.dart';

/// AdMob wrapper: optional rewarded ads and a rare interstitial between races (never during a race).
/// Every call is safe when the Mobile Ads SDK is not available (tests, unsupported platforms, no network).
class AdsService {
  AdsService(this.ref);
  final Ref ref;

  bool _initStarted = false;
  bool ready = false;
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  int racesSinceAd = 0;
  DateTime? lastAdAt;
  bool _showing = false;

  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Asks for consent (UMP) and starts the SDK. Does nothing for players who removed ads.
  Future<void> init() async {
    if (_initStarted || !supported) return;
    if (!AdPolicy.enabled(ref.read(contentProvider), ref.read(profileProvider))) return;
    _initStarted = true;
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          } catch (_) {}
          if (!done.isCompleted) done.complete();
        },
        (_) {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      if (!await ConsentInformation.instance.canRequestAds()) return;
      await MobileAds.instance.initialize();
      ready = true;
      unawaited(_loadRewarded());
      unawaited(_loadInterstitial());
    } catch (e) {
      debugPrint('ads init failed: $e');
    }
  }

  Future<void> _loadRewarded() async {
    if (!ready || _rewarded != null) return;
    try {
      await RewardedAd.load(
        adUnitId: AppConfig.admobRewardedId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(onAdLoaded: (ad) => _rewarded = ad, onAdFailedToLoad: (_) => _rewarded = null),
      );
    } catch (_) {}
  }

  Future<void> _loadInterstitial() async {
    if (!ready || _interstitial != null) return;
    try {
      await InterstitialAd.load(
        adUnitId: AppConfig.admobInterstitialId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: (ad) => _interstitial = ad, onAdFailedToLoad: (_) => _interstitial = null),
      );
    } catch (_) {}
  }

  bool get rewardedReady => ready && _rewarded != null;

  /// Shows a rewarded ad. Returns true only when the player watched it to the end.
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null || _showing) {
      unawaited(_loadRewarded());
      return false;
    }
    _rewarded = null;
    _showing = true;
    final c = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showing = false;
        lastAdAt = DateTime.now();
        racesSinceAd = 0;
        unawaited(_loadRewarded());
        if (!c.isCompleted) c.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _showing = false;
        unawaited(_loadRewarded());
        if (!c.isCompleted) c.complete(false);
      },
    );
    try {
      await ad.show(onUserEarnedReward: (_, _) => earned = true);
    } catch (_) {
      _showing = false;
      if (!c.isCompleted) c.complete(false);
    }
    return c.future;
  }

  /// Called when the player starts another race from the results screen. Counts the race and shows
  /// an interstitial only if the (remote-configurable) policy allows it.
  Future<void> betweenRaces({bool tutorialOrLesson = false}) async {
    racesSinceAd++;
    final db = ref.read(contentProvider);
    final p = ref.read(profileProvider);
    final since = lastAdAt == null ? null : DateTime.now().difference(lastAdAt!).inMilliseconds;
    if (!AdPolicy.interstitialDue(db, p, racesSinceAd: racesSinceAd, msSinceLastAd: since, tutorialOrLesson: tutorialOrLesson)) return;
    final ad = _interstitial;
    if (ad == null || _showing) {
      unawaited(_loadInterstitial());
      return;
    }
    _interstitial = null;
    _showing = true;
    final c = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _showing = false;
        lastAdAt = DateTime.now();
        racesSinceAd = 0;
        unawaited(_loadInterstitial());
        if (!c.isCompleted) c.complete();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _showing = false;
        unawaited(_loadInterstitial());
        if (!c.isCompleted) c.complete();
      },
    );
    try {
      await ad.show();
    } catch (_) {
      _showing = false;
      if (!c.isCompleted) c.complete();
    }
    await c.future.timeout(const Duration(seconds: 90), onTimeout: () {});
  }

  void dispose() {
    _rewarded?.dispose();
    _interstitial?.dispose();
  }
}

final adsProvider = Provider<AdsService>((ref) {
  final s = AdsService(ref);
  ref.onDispose(s.dispose);
  return s;
});
