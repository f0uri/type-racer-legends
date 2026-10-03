import 'licenses_screen.dart';
import '../tutorial/tutorial_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/countries.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../../data/merge/profile_merge.dart';
import '../../data/remote/firebase_boot.dart';
import '../auth/auth_controller.dart';
import '../content/content_updater.dart';
import '../update/update_ui.dart';
import 'legal_texts.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t, style: const TextStyle(color: C.cyan, fontWeight: FontWeight.w900, fontSize: 15)),
      );

  Widget _switch(WidgetRef ref, String title, String key, bool value, {String? sub}) => SwitchListTile(
        value: value,
        onChanged: (v) => ref.read(profileProvider.notifier).update((p) => p.setSetting(key, v)),
        title: Text(title),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: C.textDim, fontSize: 12)),
        contentPadding: EdgeInsets.zero,
      );

  Widget _slider(WidgetRef ref, String title, String key, double value, {double min = 0, double max = 1, int? divisions}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title),
        Slider(value: value.clamp(min, max).toDouble(), min: min, max: max, divisions: divisions, onChanged: (v) => ref.read(profileProvider.notifier).update((p) => p.setSetting(key, double.parse(v.toStringAsFixed(2))), syncSoon: false), onChangeEnd: (_) => ref.read(profileProvider.notifier).scheduleSync()),
      ]);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final p = ref.watch(profileProvider);
    final auth = ref.watch(authProvider);
    final sync = ref.watch(syncStateProvider);
    return Scaffold(
      appBar: AppBar(title: const AppBarTitle('الإعدادات')),
      body: GradientBg(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _section('الحساب'),
          Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => _pickAvatar(context, ref),
                  child: CircleAvatar(radius: 28, backgroundColor: C.surface2, child: Icon(avatars[p.avatar % avatars.length], size: 26, color: C.cyan)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${p.country.isEmpty ? '' : '${flagEmoji(p.country)} '}${p.name}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    Text(auth.isGoogle ? (auth.email ?? 'حساب جوجل') : 'زائر (محفوظ على هذا الجهاز)', style: const TextStyle(color: C.textDim, fontSize: 12)),
                  ]),
                ),
                IconButton(icon: const Icon(Icons.edit, color: C.cyan), onPressed: () => _editName(context, ref)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => _pickCountry(context, ref), icon: const Icon(Icons.flag_outlined), label: Text(p.country.isEmpty ? 'اختر الدولة' : countries[p.country] ?? p.country))),
              ]),
              const Divider(height: 24),
              if (auth.isGoogle) ...[
                Row(children: [
                  Icon(sync.phase == SyncPhase.error ? Icons.cloud_off : Icons.cloud_done, color: sync.phase == SyncPhase.error ? C.red : C.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_syncText(sync), style: const TextStyle(fontSize: 13))),
                  TextButton(onPressed: () => ref.read(profileProvider.notifier).syncNow(), child: const Text('مزامنة الآن')),
                ]),
              ] else
                NeonButton(
                  label: 'ربط حساب جوجل (دمج تقدمك بأمان)',
                  icon: Icons.account_circle,
                  color: C.magenta,
                  busy: auth.busy,
                  onPressed: () async {
                    final err = await ref.read(authProvider.notifier).signInWithGoogle();
                    if (context.mounted) toast(context, err ?? 'تم الربط وتمت مزامنة تقدمك');
                  },
                ),
              const SizedBox(height: 10),
              if (auth.isGoogle)
                TextButton.icon(onPressed: () => _restoreBackup(context, ref), icon: const Icon(Icons.restore, size: 18), label: const Text('استعادة نسخة احتياطية سحابية')),
              Row(children: [
                Expanded(child: TextButton(onPressed: auth.busy ? null : () => _signOut(context, ref), child: const Text('تسجيل الخروج', style: TextStyle(color: C.gold)))),
                Expanded(child: TextButton(onPressed: auth.busy ? null : () => _deleteAccount(context, ref), child: const Text('حذف الحساب وبياناتي', style: TextStyle(color: C.red)))),
              ]),
            ]),
          ),
          _section('الصوت والاهتزاز'),
          Panel(child: Column(children: [
            _switch(ref, 'المؤثرات الصوتية', 'sound', s.sound),
            if (s.sound) _slider(ref, 'مستوى المؤثرات', 'sfxVol', s.sfxVolume),
            _switch(ref, 'الموسيقى', 'music', s.music),
            if (s.music) _slider(ref, 'مستوى الموسيقى', 'musicVol', s.musicVolume),
            _switch(ref, 'الاهتزاز (Haptic)', 'haptics', s.haptics),
          ])),
          _section('العرض وسهولة الاستخدام'),
          Panel(child: Column(children: [
            _slider(ref, 'حجم خط النص  (${(s.fontScale * 100).round()}%)', 'fontScale', s.fontScale, min: 0.8, max: 1.6, divisions: 8),
            _switch(ref, 'خط لعسر القراءة (OpenDyslexic)', 'dyslexia', s.dyslexia),
            Align(alignment: Alignment.centerRight, child: Text('وضع عمى الألوان', style: const TextStyle(fontSize: 14))),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              for (final e in const {'none': 'عادي', 'protanopia': 'بروتانوبيا', 'deuteranopia': 'ديوترانوبيا', 'tritanopia': 'تريتانوبيا'}.entries)
                ChoiceChip(label: Text(e.value), selected: s.colorBlind == e.key, onSelected: (_) => ref.read(profileProvider.notifier).update((p) => p.setSetting('colorBlind', e.key))),
            ]),
            _switch(ref, 'مؤشر الحرف التالي', 'nextCharHint', s.nextCharHint, sub: 'يضيء الحرف المطلوب على الشاشة'),
            _switch(ref, 'وضع 30 إطاراً (توفير البطارية)', 'fps30', s.fps30),
            _switch(ref, 'تنبيه استراحة بعد جلسات طويلة', 'breakReminder', s.breakReminder),
          ])),
          _section('اللعب'),
          Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _switch(ref, 'تفعيل Backspace', 'backspace', s.backspace, sub: 'إن أُوقف: الحرف الخاطئ لا يُقبل ويجب كتابة الحرف الصحيح مباشرة'),
            const SizedBox(height: 6),
            const Text('لغة نصوص السباق'),
            Wrap(spacing: 8, children: [
              for (final e in const {'en': 'English', 'fr': 'Français', 'es': 'Español'}.entries)
                ChoiceChip(label: Text(e.value), selected: s.textLang == e.key, onSelected: (_) => ref.read(profileProvider.notifier).update((p) => p.setSetting('textLang', e.key))),
            ]),
            if (s.textLang != 'en') _switch(ref, 'قبول الحروف بدون تشكيل (é = e)', 'foldAccents', s.foldAccents),
            const SizedBox(height: 6),
            const Text('صعوبة النصوص'),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('تلقائي'), selected: s.difficulty == 0, onSelected: (_) => ref.read(profileProvider.notifier).update((p) => p.setSetting('difficulty', 0))),
              for (var i = 1; i <= 5; i++) ChoiceChip(label: Text('$i'), selected: s.difficulty == i, onSelected: (_) => ref.read(profileProvider.notifier).update((p) => p.setSetting('difficulty', i))),
            ]),
          ])),
          _section('الإشعارات والتحديثات'),
          Panel(child: Column(children: [
            _switch(ref, 'تذكير السلسلة اليومية', 'streakReminder', s.streakReminder, sub: 'تنبيه قبل انتهاء سلسلتك بساعتين'),
            _switch(ref, 'الأحداث والبطولات', 'eventNotifs', s.eventNotifs),
            _switch(ref, 'فحص التحديثات تلقائياً', 'autoUpdateCheck', s.autoUpdateCheck),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('التحقق من التحديثات الآن'), trailing: const Icon(Icons.system_update_rounded, color: C.cyan), onTap: () => manualUpdateCheck(context, ref)),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('تحديث المحتوى (نصوص، مركبات، أحداث)'), trailing: const Icon(Icons.sync_rounded, color: C.cyan), onTap: () async {
              final applied = await ref.read(contentUpdaterProvider.notifier).refresh(force: true);
              if (context.mounted) toast(context, applied ? 'تم تحديث المحتوى' : 'المحتوى محدّث');
            }),
          ])),
          _section('حول'),
          Panel(child: Column(children: [
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('سياسة الخصوصية'), trailing: const Icon(Icons.chevron_left), onTap: () => _text(context, 'سياسة الخصوصية', privacyPolicyAr)),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('شروط الاستخدام'), trailing: const Icon(Icons.chevron_left), onTap: () => _text(context, 'شروط الاستخدام', termsAr)),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('التراخيص والمصادر'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const LicensesScreen()))),
            ListTile(contentPadding: EdgeInsets.zero, title: const Text('إعادة الشرح التفاعلي'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const TutorialScreen()))),
            Text(FirebaseBoot.available ? 'Firebase: متصل بالإعدادات' : 'Firebase: غير مُعدّ (وضع Offline)', style: const TextStyle(color: C.textDim, fontSize: 12)),
          ])),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  String _syncText(SyncState s) {
    switch (s.phase) {
      case SyncPhase.syncing:
        return 'جارٍ المزامنة...';
      case SyncPhase.ok:
        return 'تمت المزامنة';
      case SyncPhase.error:
        return 'تعذّرت المزامنة، سيُعاد المحاولة تلقائياً. تقدمك محفوظ محلياً.';
      default:
        return s.last == null ? 'مرتبط بحساب جوجل' : 'آخر مزامنة ناجحة';
    }
  }

  void _text(BuildContext c, String title, String body) => Navigator.push(c, MaterialPageRoute(builder: (_) => LegalScreen(title: title, body: body)));

  Future<void> _editName(BuildContext c, WidgetRef ref) async {
    final ctrl = TextEditingController(text: ref.read(profileProvider).name);
    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: const Text('اسم اللاعب'),
        content: TextField(controller: ctrl, maxLength: 14, autofocus: true, decoration: const InputDecoration(hintText: 'اكتب اسمك')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ'))],
      ),
    );
    final n = ctrl.text.trim();
    if (ok == true && n.isNotEmpty) ref.read(profileProvider.notifier).update((p) => p.setIdentity(name: n));
  }

  Future<void> _pickAvatar(BuildContext c, WidgetRef ref) async {
    final current = ref.read(profileProvider).avatar;
    final i = await showModalBottomSheet<int>(
      context: c,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < avatars.length; i++) GestureDetector(onTap: () => Navigator.pop(ctx, i), child: CircleAvatar(radius: 28, backgroundColor: C.surface2, child: Icon(avatars[i], size: 26, color: i == current ? C.cyan : C.textDim))),
        ]),
      ),
    );
    if (i != null) ref.read(profileProvider.notifier).update((p) => p.setIdentity(avatar: i));
  }

  Future<void> _pickCountry(BuildContext c, WidgetRef ref) async {
    final code = await showModalBottomSheet<String>(
      context: c,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * .7,
        child: ListView(children: [for (final e in countries.entries) ListTile(leading: Text(flagEmoji(e.key), style: const TextStyle(fontSize: 24)), title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key))]),
      ),
    );
    if (code != null) ref.read(profileProvider.notifier).update((p) => p.setIdentity(country: code));
  }

  Future<void> _signOut(BuildContext c, WidgetRef ref) async {
    if (!await confirmDialog(c, 'تسجيل الخروج', ref.read(authProvider).isGoogle ? 'سيتم حفظ تقدمك سحابياً ثم تسجيل خروجك. يمكنك العودة في أي وقت بنفس الحساب.' : 'سيُحفظ تقدم الزائر كنسخة محلية مؤرشفة ثم تبدأ من شاشة الدخول.')) return;
    final err = await ref.read(authProvider.notifier).signOut();
    if (c.mounted && err != null) toast(c, err);
    if (c.mounted) Navigator.of(c).popUntil((r) => r.isFirst);
  }

  Future<void> _deleteAccount(BuildContext c, WidgetRef ref) async {
    if (!await confirmDialog(c, 'حذف الحساب', 'سيتم حذف حسابك وكل بياناتك (السحابية والمحلية) نهائياً ولا يمكن التراجع. هل أنت متأكد؟', ok: 'احذف نهائياً', okColor: C.red)) return;
    final err = await ref.read(authProvider.notifier).deleteAccount();
    if (c.mounted && err != null) toast(c, err);
    if (c.mounted) Navigator.of(c).popUntil((r) => r.isFirst);
  }

  Future<void> _restoreBackup(BuildContext c, WidgetRef ref) async {
    try {
      final list = await ref.read(cloudSyncProvider).backups();
      if (list.isEmpty) {
        if (c.mounted) toast(c, 'لا توجد نسخ احتياطية بعد');
        return;
      }
      ref.read(profileProvider.notifier).update((p) {
        // Merge (never overwrite) so nothing is lost.
        final merged = ref.read(profileProvider).clone();
        for (final b in list) {
          final m = ProfileMerger.merge(merged, b);
          merged.d
            ..clear()
            ..addAll(m.d);
        }
        p.d
          ..clear()
          ..addAll(merged.d);
      });
      if (c.mounted) toast(c, 'تمت استعادة النسخة الاحتياطية بدمج آمن');
    } catch (e) {
      if (c.mounted) toast(c, 'تعذّر جلب النسخ الاحتياطية');
    }
  }

}

class LegalScreen extends StatelessWidget {
  final String title, body;
  const LegalScreen({super.key, required this.title, required this.body});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: AppBarTitle(title)),
        body: GradientBg(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Text(body, style: const TextStyle(height: 1.9, fontSize: 14)))),
      );
}
