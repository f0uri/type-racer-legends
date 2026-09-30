/// Build-time configuration. Values can be overridden with --dart-define.
class AppConfig {
  static const appName = 'Type Racer Legends';
  static const githubRepo = String.fromEnvironment('GITHUB_REPO', defaultValue: 'f0uri/type-racer-legends');
  static const contentBaseUrl = String.fromEnvironment('CONTENT_BASE_URL', defaultValue: 'https://f0uri.github.io/type-racer-legends/content');
  static const updateJsonUrl = String.fromEnvironment('UPDATE_JSON_URL', defaultValue: 'https://f0uri.github.io/type-racer-legends/version.json');
  static const challengeLandingUrl = String.fromEnvironment('CHALLENGE_URL', defaultValue: 'https://f0uri.github.io/type-racer-legends/c/');
  /// Must match setGlobalOptions({ region }) in functions/index.js.
  static const functionsRegion = 'europe-west1';
  static const deepLinkScheme = 'typeracerlegends';
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL', defaultValue: '');

  // AdMob: Google test ids by default.
  static const admobRewardedId = String.fromEnvironment('ADMOB_REWARDED_ID', defaultValue: 'ca-app-pub-3940256099942544/5224354917');
  static const admobInterstitialId = String.fromEnvironment('ADMOB_INTERSTITIAL_ID', defaultValue: 'ca-app-pub-3940256099942544/1033173712');

  static const minContentSchema = 1;
  static const maxHumanWpm = 240;
  static const profileSchema = 1;
}
