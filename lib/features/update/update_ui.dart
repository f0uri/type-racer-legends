import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../content/content_updater.dart';
import 'update_controller.dart';

/// Wraps the app: runs the startup check, shows the optional-update dialog once per session,
/// and blocks the whole app with a full-screen page when the update is mandatory.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  bool _dialogShown = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(const Duration(seconds: 4), () {
      if (mounted) ref.read(updateProvider.notifier).check();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<UpdateState>(updateProvider, (prev, next) {
      final nav = navigatorKey.currentContext;
      if (nav == null) return;
      if (next.phase == UpdatePhase.playDownloaded && prev?.phase != UpdatePhase.playDownloaded) {
        ScaffoldMessenger.maybeOf(nav)?.showSnackBar(SnackBar(
          content: const Text('تم تنزيل التحديث'),
          duration: const Duration(seconds: 12),
          action: SnackBarAction(label: 'أعد التشغيل الآن', onPressed: () => ref.read(updateProvider.notifier).completePlayUpdate()),
        ));
      }
      if (next.phase == UpdatePhase.available && !next.mandatory && !_dialogShown && !ref.read(updateProvider.notifier).snoozed) {
        _dialogShown = true;
        showUpdateDialog(nav);
      }
    });
    final s = ref.watch(updateProvider);
    final block = s.mandatory && s.hasUpdate && !s.viaPlay;
    return Stack(children: [
      widget.child,
      if (block) const Positioned.fill(child: MandatoryUpdateScreen()),
    ]);
  }
}

Future<void> showUpdateDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(insetPadding: EdgeInsets.all(16), child: Padding(padding: EdgeInsets.all(18), child: UpdatePanel(dialog: true))),
    );

class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({super.key});
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Material(
          color: C.bg,
          child: GradientBg(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: Column(mainAxisSize: MainAxisSize.min, children: const [
                      const Icon(Icons.rocket_launch, size: 64, color: C.cyan),
                      SizedBox(height: 10),
                      Text('تحديث إلزامي', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      SizedBox(height: 6),
                      Text('هذا الإصدار لم يعد مدعوماً. حدّث اللعبة للمتابعة — تقدمك محفوظ بالكامل.', textAlign: TextAlign.center, style: TextStyle(color: C.textDim)),
                      SizedBox(height: 20),
                      UpdatePanel(dialog: false),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// State-driven update UI: notes -> (mobile data warning) -> progress with cancel -> permission explanation -> installer.
class UpdatePanel extends ConsumerStatefulWidget {
  const UpdatePanel({super.key, required this.dialog});
  final bool dialog;
  @override
  ConsumerState<UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends ConsumerState<UpdatePanel> {
  bool _autoInstalled = false;

  Future<void> _start() async {
    final c = ref.read(updateProvider.notifier);
    final info = ref.read(updateProvider).info;
    if (info == null) return;
    final kind = await c.connectionKind();
    if (!mounted) return;
    if (kind == 'none') {
      toast(context, 'لا يوجد اتصال بالإنترنت');
      return;
    }
    if (kind == 'mobile') {
      final dlgCtx = navigatorKey.currentContext ?? context;
      final ok = await confirmDialog(dlgCtx, 'بيانات الجوال', 'أنت متصل عبر بيانات الجوال. حجم التحديث ${info.sizeLabel}. هل تريد المتابعة؟', ok: 'تنزيل', cancel: 'انتظر الواي فاي', okColor: C.gold);
      if (!ok) return;
    }
    _autoInstalled = false;
    await c.startDownload();
  }

  Future<void> _grant() async {
    final c = ref.read(updateProvider.notifier);
    final ok = await c.requestInstallPermission();
    if (!mounted) return;
    if (ok) {
      await c.install();
    } else {
      toast(context, 'لم تُمنح صلاحية التثبيت. يمكنك منحها من إعدادات النظام ثم المحاولة مجدداً.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(updateProvider);
    final c = ref.read(updateProvider.notifier);
    final info = s.info;
    if (s.phase == UpdatePhase.downloaded && !_autoInstalled) {
      _autoInstalled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.install();
      });
    }
    final notes = info?.notesAr ?? '';
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.dialog) Text('إصدار جديد ${info?.versionName ?? ''}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
        if (!widget.dialog && info != null) Center(child: Text('الإصدار ${info.versionName}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: C.cyan))),
        const SizedBox(height: 8),
        if (notes.isNotEmpty && (s.phase == UpdatePhase.available || s.phase == UpdatePhase.error))
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
            child: SingleChildScrollView(child: Text(notes, style: const TextStyle(fontSize: 13, height: 1.5))),
          ),
        if (info != null && s.phase == UpdatePhase.available) Padding(padding: const EdgeInsets.only(top: 6), child: Text('الحجم: ${info.sizeLabel}', style: const TextStyle(color: C.textDim, fontSize: 12))),
        const SizedBox(height: 12),
        ..._body(s, c),
      ]),
    );
  }

  List<Widget> _body(UpdateState s, UpdateController c) {
    switch (s.phase) {
      case UpdatePhase.available:
        return [
          NeonButton(label: 'تحديث الآن', icon: Icons.system_update_rounded, onPressed: _start),
          if (!s.mandatory) TextButton(onPressed: () async {
                await c.snooze();
                if (mounted && widget.dialog) Navigator.of(context).pop();
              }, child: const Text('لاحقاً (تذكير بعد يوم)')),
        ];
      case UpdatePhase.downloading:
        final pct = (s.progress * 100).clamp(0, 100).toStringAsFixed(0);
        final mb = (s.received / 1048576).toStringAsFixed(1);
        final total = s.info == null ? '' : ' / ${(s.info!.size / 1048576).toStringAsFixed(1)} MB';
        return [
          if (s.viaPlay) const Center(child: CircularProgressIndicator()) else ProgressBar(value: s.progress, height: 12),
          const SizedBox(height: 8),
          if (!s.viaPlay) Center(child: Text('$pct%   ($mb MB$total)', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w800))),
          if (!s.viaPlay) TextButton(onPressed: c.cancelDownload, child: const Text('إلغاء التنزيل')),
        ];
      case UpdatePhase.downloaded:
      case UpdatePhase.installing:
        return [
          const Center(child: Text('تم التنزيل والتحقق من سلامة الملف', style: TextStyle(color: C.green, fontWeight: FontWeight.w800))),
          const SizedBox(height: 8),
          NeonButton(label: 'تثبيت الآن', icon: Icons.install_mobile_rounded, busy: s.phase == UpdatePhase.installing, onPressed: c.install),
        ];
      case UpdatePhase.needsInstallPermission:
        return [
          const Panel(
            border: C.gold,
            child: Text(
              'لتثبيت التحديث يحتاج أندرويد إلى إذنك بالسماح لهذه اللعبة بتثبيت التطبيقات (صلاحية REQUEST_INSTALL_PACKAGES).\n\nسنستخدمها فقط لتثبيت ملف التحديث الذي تحققنا من سلامته (SHA-256). ستظهر لك شاشة إعدادات النظام: فعّل «السماح من هذا المصدر» ثم ارجع إلى اللعبة.',
              style: TextStyle(height: 1.6, fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          NeonButton(label: 'منح الإذن ومتابعة التثبيت', icon: Icons.verified_user_rounded, color: C.gold, onPressed: _grant),
        ];
      case UpdatePhase.error:
        return [
          Text(s.error ?? 'حدث خطأ', style: const TextStyle(color: C.red)),
          const SizedBox(height: 8),
          NeonButton(label: 'إعادة المحاولة', icon: Icons.refresh_rounded, onPressed: _start),
          if (!s.mandatory) TextButton(onPressed: () {
                c.dismissError();
                if (widget.dialog) Navigator.of(context).pop();
              }, child: const Text('إغلاق')),
        ];
      default:
        return [if (widget.dialog) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('إغلاق'))];
    }
  }
}

/// Manual "check for updates" used by the settings screen.
Future<void> manualUpdateCheck(BuildContext context, WidgetRef ref) async {
  final c = ref.read(updateProvider.notifier);
  toast(context, 'جارٍ التحقق من التحديثات...');
  await c.check(manual: true);
  if (!context.mounted) return;
  final s = ref.read(updateProvider);
  if (s.hasUpdate) {
    await showUpdateDialog(context);
  } else {
    final v = (await ref.read(appInfoProvider.future)).versionName;
    if (context.mounted) toast(context, 'أنت على أحدث إصدار ($v)');
  }
}

