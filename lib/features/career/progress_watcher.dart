import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../core/providers.dart';
import '../../core/services/audio_service.dart';
import '../../core/widgets/common.dart';
import '../../data/models/profile.dart';
import 'progress.dart';

/// Watches the profile: after every change it sets up quests/season, unlocks achievements and announces them.
class ProgressWatcher extends ConsumerStatefulWidget {
  const ProgressWatcher({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ProgressWatcher> createState() => _ProgressWatcherState();
}

class _ProgressWatcherState extends ConsumerState<ProgressWatcher> {
  Timer? _t;
  int _lastClaimable = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _schedule() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), _run);
  }

  void _run() {
    if (!mounted) return;
    final db = ref.read(contentProvider);
    final p = ref.read(profileProvider);
    if (db.quests.isEmpty && db.achievements.isEmpty) return;
    if (Progression.needsWork(db, p)) {
      var report = ProgressReport(const []);
      ref.read(profileProvider.notifier).update((pp) => report = Progression.evaluate(db, pp));
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted && report.achievements.isNotEmpty) {
        ref.read(audioProvider).play(Sfx.levelUp);
        final first = report.achievements.first;
        toast(ctx, 'إنجاز جديد: ${(first.name['ar'] ?? first.name['en'] ?? first.id)}${report.achievements.length > 1 ? ' (+${report.achievements.length - 1})' : ''}');
      }
    }
    final now = ref.read(profileProvider);
    final claimable = Quests.claimable(db, now);
    if (_lastClaimable >= 0 && claimable > _lastClaimable) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) toast(ctx, 'أنجزت مهمة! اذهب إلى «التقدم» لاستلام المكافأة');
    }
    _lastClaimable = claimable;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PlayerProfile>(profileProvider, (_, _) => _schedule());
    ref.listen(contentProvider, (_, _) => _schedule());
    return widget.child;
  }
}
