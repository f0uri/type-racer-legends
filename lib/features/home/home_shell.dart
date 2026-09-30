import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../content/content_updater.dart';
import '../content/new_items.dart';
import '../../core/theme/app_theme.dart';
import '../garage/garage_screen.dart';
import '../shop/shop_screen.dart';
import 'home_screen.dart';

/// Bottom navigation hosting the main tabs.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _i = widget.initialTab;

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final unseen = ref.watch(unseenItemsProvider).length;
    final tabs = <Widget>[
      const HomeScreen(),
      const GarageScreen(embedded: true),
      const ShopScreen(embedded: true),
    ];
    return Scaffold(
      body: IndexedStack(index: _i, children: tabs),
      bottomNavigationBar: NavigationBar(
        backgroundColor: C.surface,
        indicatorColor: C.cyan.withValues(alpha: 0.2),
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag_rounded), label: 'السباق'),
          NavigationDestination(icon: Badge(isLabelVisible: unseen > 0, label: Text('$unseen'), child: const Icon(Icons.directions_car_outlined)), selectedIcon: const Icon(Icons.directions_car_rounded), label: 'الكراج'),
          const NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront_rounded), label: 'المتجر'),
        ],
      ),
    );
  }
}
