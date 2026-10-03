import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../ads/ads_service.dart';
import '../career/progress.dart';
import '../notifications/engagement.dart';
import '../tutorial/tutorial_screen.dart';
import '../career/progress_screen.dart';
import '../content/content_updater.dart';
import '../shop/iap_service.dart';
import '../content/new_items.dart';
import '../../core/theme/app_theme.dart';
import '../garage/garage_screen.dart';
import '../shop/shop_screen.dart';
import '../profile/profile_screen.dart';
import 'home_screen.dart';

/// Main game shell.
///
/// Not a `NavigationBar`: games do not have browser-like tabs. The player gets one immersive
/// screen with content in front of them and a floating, glowing dock of five destinations whose
/// highlight *slides* between items. Every tap answers with a haptic tick so the UI feels physical.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _i = widget.initialTab;
  Timer? _adsTimer;

  static const _dockSpace = 72.0;

  @override
  void dispose() {
    _adsTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final db = ref.read(contentProvider);
      final p = ref.read(profileProvider);
      if (!p.flag(NewItems.baselineFlag)) {
        ref.read(profileProvider.notifier).update((pp) => NewItems.ensureBaseline(db, pp), syncSoon: false);
      }
      // opening the app counts as the daily login for the streak
      ref.read(profileProvider.notifier).update((pp) => LoginStreak.register(pp));
      if (LoginStreak.claimable(ref.read(profileProvider))) _showLoginReward();
      ref.read(iapProvider.notifier).start();
      if (!ref.read(profileProvider).flag('tutorialDone')) {
        _offerTutorial();
      } else {
        ref.read(engagementProvider).startup();
      }
      // ads start a few seconds later so they never compete with the first screen
      _adsTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) ref.read(adsProvider).init();
      });
    });
  }

  Future<void> _offerTutorial() async {
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('🏁 جديد في اللعبة؟'),
        content: const Text('جرّب الشرح التفاعلي (دقيقة واحدة) واحصل على 200 عملة هدية. يمكنك إعادته من الإعدادات.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('تخطّي')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ابدأ الشرح')),
        ],
      ),
    );
    if (!mounted) return;
    if (go == true) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TutorialScreen()));
    } else {
      ref.read(profileProvider.notifier).update((p) => p.setFlag('tutorialDone'));
    }
    if (mounted) ref.read(engagementProvider).startup();
  }

  void _showLoginReward() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('مرحباً بعودتك! 🎁', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            const LoginStreakCard(),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('إغلاق')),
          ]),
        ),
      ),
    );
  }

  void _select(int i) {
    if (i == _i) return;
    ref.read(hapticsProvider).light(); // every tap answers: this is what makes a UI feel physical
    setState(() => _i = i);
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(contentProvider);
    final prof = ref.watch(profileProvider);
    final badge = progressBadgeCount(db, prof);
    final unseen = ref.watch(unseenItemsProvider).length;
    final tabs = <Widget>[
      const HomeScreen(),
      const GarageScreen(embedded: true),
      const ShopScreen(embedded: true),
      const ProgressScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      backgroundColor: C.bg,
      body: Stack(
        children: [
          Padding(padding: const EdgeInsets.only(bottom: _dockSpace), child: IndexedStack(index: _i, children: tabs)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Dock(
              index: _i,
              onSelect: _select,
              items: [
                const _DockItem(icon: Icons.flag_rounded, label: 'السباق'),
                _DockItem(icon: Icons.directions_car_rounded, label: 'الكراج', badge: unseen),
                const _DockItem(icon: Icons.storefront_rounded, label: 'المتجر'),
                _DockItem(icon: Icons.emoji_events_rounded, label: 'التقدم', badge: badge),
                const _DockItem(icon: Icons.person_rounded, label: 'ملفي'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DockItem {
  final IconData icon;
  final String label;
  final int badge;
  const _DockItem({required this.icon, required this.label, this.badge = 0});
}

/// Floating game dock: dark glass bar, the selected icon rides on a glowing pill that *slides*
/// between destinations, and the selected icon gently breathes (always-something-alive).
class _Dock extends StatelessWidget {
  const _Dock({required this.index, required this.items, required this.onSelect});
  final int index;
  final List<_DockItem> items;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        border: Border(top: BorderSide(color: C.cyan.withValues(alpha: 0.18))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: LayoutBuilder(
            builder: (context, cons) {
              final w = cons.maxWidth / items.length;
              return Stack(
                children: [
                  AnimatedPositionedDirectional(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    start: w * index,
                    width: w,
                    top: 10,
                    bottom: 10,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [C.cyan.withValues(alpha: 0.30), C.magenta.withValues(alpha: 0.22)]),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: C.cyan.withValues(alpha: 0.55)),
                          boxShadow: [BoxShadow(color: C.cyan.withValues(alpha: 0.35), blurRadius: 14)],
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        Expanded(
                          child: _DockButton(item: items[i], selected: i == index, onTap: () => onSelect(i)),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatefulWidget {
  const _DockButton({required this.item, required this.selected, required this.onTap});
  final _DockItem item;
  final bool selected;
  final VoidCallback onTap;
  @override
  State<_DockButton> createState() => _DockButtonState();
}

class _DockButtonState extends State<_DockButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final color = sel ? C.cyan : C.textDim;
    final icon = Badge(
      isLabelVisible: widget.item.badge > 0,
      label: Text('${widget.item.badge}'),
      child: Icon(widget.item.icon, size: 23, color: color),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            duration: const Duration(milliseconds: 200),
            scale: sel ? 1.12 : 1,
            child: sel
                ? AnimatedBuilder(
                    animation: _c,
                    builder: (_, child) => Transform.translate(offset: Offset(0, -1.2 * _c.value), child: child),
                    child: icon,
                  )
                : icon,
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(fontSize: 10.5, fontWeight: sel ? FontWeight.w900 : FontWeight.w600, color: color, fontFamily: 'Tajawal'),
            child: Text(widget.item.label),
          ),
        ],
      ),
    );
  }
}
