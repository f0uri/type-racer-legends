import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../content/content_updater.dart';
import 'apk_downloader.dart';
import 'version_info.dart';

enum UpdatePhase { idle, checking, upToDate, available, downloading, downloaded, needsInstallPermission, installing, playDownloaded, error }

class UpdateState {
  final UpdatePhase phase;
  final VersionInfo? info;
  final bool mandatory;
  final double progress;
  final int received;
  final String? error;
  final bool viaPlay;
  final String? apkPath;
  const UpdateState({this.phase = UpdatePhase.idle, this.info, this.mandatory = false, this.progress = 0, this.received = 0, this.error, this.viaPlay = false, this.apkPath});

  UpdateState copy({UpdatePhase? phase, VersionInfo? info, bool? mandatory, double? progress, int? received, String? error, bool? viaPlay, String? apkPath}) => UpdateState(
        phase: phase ?? this.phase,
        info: info ?? this.info,
        mandatory: mandatory ?? this.mandatory,
        progress: progress ?? this.progress,
        received: received ?? this.received,
        error: error,
        viaPlay: viaPlay ?? this.viaPlay,
        apkPath: apkPath ?? this.apkPath,
      );

  bool get hasUpdate => const [UpdatePhase.available, UpdatePhase.downloading, UpdatePhase.downloaded, UpdatePhase.needsInstallPermission, UpdatePhase.installing, UpdatePhase.playDownloaded].contains(phase) || (phase == UpdatePhase.error && info != null);
}

/// Pure decision used by the controller and tests.
class UpdateDecision {
  final bool available;
  final bool mandatory;
  const UpdateDecision(this.available, this.mandatory);

  static UpdateDecision decide({required int currentCode, required VersionInfo? info, int remoteMinSupported = 0}) {
    if (info == null) return const UpdateDecision(false, false); // nothing installable is known
    final available = info.versionCode > currentCode;
    final mandatory = available && info.isMandatoryFor(currentCode, remoteMin: remoteMinSupported);
    return UpdateDecision(available, mandatory);
  }
}

class UpdateController extends Notifier<UpdateState> {
  static const snoozeKey = 'updateSnoozeUntil';
  CancelToken? _cancel;
  ApkDownloader? _downloader;

  @override
  UpdateState build() => const UpdateState();

  DateTime? get snoozedUntil {
    final ms = ref.read(storeProvider).meta.get(snoozeKey) as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get snoozed => !state.mandatory && snoozedUntil != null && DateTime.now().isBefore(snoozedUntil!);

  /// Optional updates are hidden for one day after "later".
  Future<void> snooze() => ref.read(storeProvider).meta.put(snoozeKey, DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch);

  Future<VersionInfo?> _fetchInfo() async {
    final store = ref.read(storeProvider);
    try {
      final res = await http.get(Uri.parse(AppConfig.updateJsonUrl), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final j = jsonDecode(utf8.decode(res.bodyBytes));
        final v = VersionInfo.tryParse(j);
        if (v != null) {
          await store.meta.put('versionJson', jsonEncode(j));
          return v;
        }
      }
    } catch (e) {
      debugPrint('version.json unavailable: $e');
    }
    final cached = store.meta.get('versionJson') as String?;
    if (cached == null) return null;
    try {
      return VersionInfo.tryParse(jsonDecode(cached));
    } catch (_) {
      return null;
    }
  }

  /// Checks for updates. [manual] shows "up to date" feedback and ignores the snooze.
  Future<void> check({bool manual = false}) async {
    if (state.phase == UpdatePhase.checking || state.phase == UpdatePhase.downloading || state.phase == UpdatePhase.installing) return;
    if (!manual && !ref.read(settingsProvider).autoUpdateCheck) return;
    final previous = state;
    state = state.copy(phase: UpdatePhase.checking);
    try {
      final app = await ref.read(appInfoProvider.future);
      final remoteMin = ref.read(contentProvider.notifier).remote.minSupportedVersion ?? 0;
      final info = await _fetchInfo();
      final decision = UpdateDecision.decide(currentCode: app.versionCode, info: info, remoteMinSupported: remoteMin);
      // Play installs update through Google Play only (flexible, or immediate below the minimum supported version)
      if (app.fromPlayStore) {
        final belowMin = app.versionCode < (info?.minSupportedVersion ?? 0) || app.versionCode < remoteMin || (info?.mandatory == true && decision.available);
        final played = await _playCheck(belowMin);
        if (played) return;
        state = UpdateState(phase: UpdatePhase.upToDate, viaPlay: true, info: info);
        return;
      }
      if (info != null && decision.available) {
        state = UpdateState(phase: UpdatePhase.available, info: info, mandatory: decision.mandatory);
        return;
      }
      state = UpdateState(phase: UpdatePhase.upToDate, info: info);
    } catch (e) {
      debugPrint('update check failed: $e');
      state = previous.phase == UpdatePhase.checking ? const UpdateState(phase: UpdatePhase.upToDate) : previous;
    }
  }

  Future<bool> _playCheck(bool mustUpdate) async {
    try {
      final pi = await InAppUpdate.checkForUpdate();
      if (pi.updateAvailability != UpdateAvailability.updateAvailable && pi.updateAvailability != UpdateAvailability.developerTriggeredUpdateInProgress) return false;
      if (mustUpdate && pi.immediateUpdateAllowed) {
        state = const UpdateState(phase: UpdatePhase.installing, mandatory: true, viaPlay: true);
        final r = await InAppUpdate.performImmediateUpdate();
        if (r != AppUpdateResult.success) state = const UpdateState(phase: UpdatePhase.available, mandatory: true, viaPlay: true);
        return true;
      }
      if (pi.flexibleUpdateAllowed && !snoozed) {
        state = const UpdateState(phase: UpdatePhase.downloading, viaPlay: true);
        final r = await InAppUpdate.startFlexibleUpdate();
        if (r == AppUpdateResult.success) {
          state = const UpdateState(phase: UpdatePhase.playDownloaded, viaPlay: true);
        } else {
          state = const UpdateState(phase: UpdatePhase.upToDate, viaPlay: true);
          await snooze();
        }
        return true;
      }
    } catch (e) {
      debugPrint('play update unavailable: $e');
    }
    return false;
  }

  Future<void> completePlayUpdate() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('complete flexible update failed: $e');
    }
  }

  /// "wifi" | "mobile" | "none" — used for the data-usage warning.
  Future<String> connectionKind() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) return 'wifi';
      if (r.contains(ConnectivityResult.mobile)) return 'mobile';
      if (r.isEmpty || r.every((e) => e == ConnectivityResult.none)) return 'none';
      return 'wifi';
    } catch (_) {
      return 'wifi';
    }
  }

  Future<Directory> _dir() async {
    final base = await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    return Directory('${base.path}/updates');
  }

  @visibleForTesting
  Directory? dirOverride;

  Future<void> startDownload() async {
    final info = state.info;
    if (info == null || state.phase == UpdatePhase.downloading) return;
    _cancel = CancelToken();
    _downloader?.close();
    _downloader = ApkDownloader();
    state = state.copy(phase: UpdatePhase.downloading, progress: 0, received: 0);
    try {
      final dir = dirOverride ?? await _dir();
      await _downloader!.clean(dir, keepCode: info.versionCode);
      final f = await _downloader!.download(info, dir, cancel: _cancel, onProgress: (got, total) {
        state = state.copy(phase: UpdatePhase.downloading, progress: total == 0 ? 0 : got / total, received: got);
      });
      state = state.copy(phase: UpdatePhase.downloaded, progress: 1, apkPath: f.path);
    } on DownloadCancelled {
      state = state.copy(phase: UpdatePhase.available, error: null);
    } on HashMismatch {
      state = state.copy(phase: UpdatePhase.error, error: 'فشل التحقق من سلامة الملف (SHA-256). أُعيد التنزيل من البداية عند المحاولة التالية.');
    } catch (e) {
      state = state.copy(phase: UpdatePhase.error, error: 'تعذّر تنزيل التحديث. تحقق من الاتصال ثم أعد المحاولة — سيُستأنف التنزيل من حيث توقف.');
      debugPrint('download failed: $e');
    }
  }

  void cancelDownload() => _cancel?.cancel();

  Future<bool> installPermissionGranted() async {
    try {
      return await Permission.requestInstallPackages.isGranted;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestInstallPermission() async {
    try {
      final r = await Permission.requestInstallPackages.request();
      return r.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Launches the system installer for the verified APK.
  Future<void> install() async {
    final path = state.apkPath;
    if (path == null) return;
    if (!await installPermissionGranted()) {
      state = state.copy(phase: UpdatePhase.needsInstallPermission);
      return;
    }
    state = state.copy(phase: UpdatePhase.installing);
    try {
      final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) {
        state = state.copy(phase: UpdatePhase.error, error: 'تعذّر فتح مثبّت التطبيقات: ${r.message}');
      } else {
        state = state.copy(phase: UpdatePhase.downloaded);
      }
    } catch (e) {
      state = state.copy(phase: UpdatePhase.error, error: 'تعذّر بدء التثبيت.');
    }
  }

  void dismissError() => state = state.copy(phase: state.info != null ? UpdatePhase.available : UpdatePhase.upToDate);
}

final updateProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);
