import 'package:package_info_plus/package_info_plus.dart';

/// Version / installer information about the running app (safe fallbacks when the plugin is unavailable, e.g. in tests).
class AppInfo {
  final String versionName;
  final int versionCode;
  final String? installer;
  const AppInfo(this.versionName, this.versionCode, this.installer);

  static const fallback = AppInfo('0.0.0', 1, null);

  bool get fromPlayStore => installer == 'com.android.vending';

  static Future<AppInfo> load() async {
    try {
      final i = await PackageInfo.fromPlatform();
      return AppInfo(i.version, int.tryParse(i.buildNumber) ?? 1, i.installerStore);
    } catch (_) {
      return fallback;
    }
  }
}
