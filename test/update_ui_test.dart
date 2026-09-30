import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:type_racer_legends/core/theme/app_theme.dart';
import 'package:type_racer_legends/features/update/update_controller.dart';
import 'package:type_racer_legends/features/update/update_ui.dart';
import 'package:type_racer_legends/features/update/version_info.dart';

class FakeUpdate extends UpdateController {
  FakeUpdate(this.initial);
  final UpdateState initial;
  bool started = false, installed = false;
  @override
  UpdateState build() => initial;
  @override
  Future<void> startDownload() async => started = true;
  @override
  Future<void> install() async => installed = true;
  @override
  Future<String> connectionKind() async => 'wifi';
}

final info = VersionInfo(versionCode: 300, versionName: '3.0.0', apkUrl: 'https://github.com/x/a.apk', size: 48 * 1048576, sha256: 'a' * 64, notes: const {'ar': '• سباقات جديدة\n• إصلاحات'}, minSupportedVersion: 1, mandatory: false);

Future<void> pumpPanel(WidgetTester t, UpdateState s, {bool dialog = true}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [updateProvider.overrideWith(() => FakeUpdate(s))],
    child: MaterialApp(theme: buildTheme(), home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: UpdatePanel(dialog: dialog))))),
  ));
  await t.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('available: shows notes, size and offers update or snooze (optional)', (t) async {
    await pumpPanel(t, UpdateState(phase: UpdatePhase.available, info: info));
    expect(find.textContaining('سباقات جديدة'), findsOneWidget);
    expect(find.textContaining('48.0 MB'), findsOneWidget);
    expect(find.text('تحديث الآن'), findsOneWidget);
    expect(find.textContaining('لاحقاً'), findsOneWidget);
    await t.tap(find.text('تحديث الآن'));
    await t.pump(const Duration(milliseconds: 200));
    final c = ProviderScope.containerOf(t.element(find.byType(UpdatePanel)));
    expect((c.read(updateProvider.notifier) as FakeUpdate).started, isTrue);
  });

  testWidgets('mandatory updates cannot be postponed', (t) async {
    await pumpPanel(t, UpdateState(phase: UpdatePhase.available, info: info, mandatory: true), dialog: false);
    expect(find.text('تحديث الآن'), findsOneWidget);
    expect(find.textContaining('لاحقاً'), findsNothing);
  });

  testWidgets('downloading shows progress and a cancel button', (t) async {
    await pumpPanel(t, UpdateState(phase: UpdatePhase.downloading, info: info, progress: 0.42, received: 20 * 1048576));
    expect(find.textContaining('42%'), findsOneWidget);
    expect(find.text('إلغاء التنزيل'), findsOneWidget);
  });

  testWidgets('install permission is explained in Arabic before the system screen', (t) async {
    await pumpPanel(t, UpdateState(phase: UpdatePhase.needsInstallPermission, info: info, apkPath: '/tmp/a.apk'));
    expect(find.textContaining('REQUEST_INSTALL_PACKAGES'), findsOneWidget);
    expect(find.textContaining('SHA-256'), findsOneWidget);
    expect(find.text('منح الإذن ومتابعة التثبيت'), findsOneWidget);
  });

  testWidgets('downloaded APK triggers the installer once', (t) async {
    await pumpPanel(t, UpdateState(phase: UpdatePhase.downloaded, info: info, apkPath: '/tmp/a.apk'));
    await t.pump(const Duration(milliseconds: 200));
    final c = ProviderScope.containerOf(t.element(find.byType(UpdatePanel)));
    expect((c.read(updateProvider.notifier) as FakeUpdate).installed, isTrue);
    expect(find.textContaining('SHA-256'), findsNothing);
    expect(find.textContaining('تم التنزيل والتحقق'), findsOneWidget);
  });

  testWidgets('errors offer a retry', (t) async {
    await pumpPanel(t, UpdateState(phase: UpdatePhase.error, info: info, error: 'تعذّر تنزيل التحديث'));
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  testWidgets('the full-screen mandatory page blocks the app', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [updateProvider.overrideWith(() => FakeUpdate(UpdateState(phase: UpdatePhase.available, info: info, mandatory: true)))],
      child: MaterialApp(theme: buildTheme(), home: const UpdateGate(child: Scaffold(body: Text('app content')))),
    ));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('تحديث إلزامي'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 5));
  });
}
