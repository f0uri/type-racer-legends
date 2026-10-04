import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/career/progress_watcher.dart';
import 'features/home/home_shell.dart';
import 'features/lifecycle/app_lifecycle.dart';
import 'features/update/update_ui.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class TypeRacerApp extends ConsumerWidget {
  const TypeRacerApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final auth = ref.watch(authProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Type Racer Legends',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dyslexia: s.dyslexia),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        // Material/Widgets delegates are provided by default for the locale; explicit RTL handled below.
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          // The game's layout is designed at 1.0, and every screen is swept at that size in CI.
          // But a player who raised the system font size did it for a reason: honoring it up to
          // 1.3x costs nothing (the sweep covers 1.3 too) and never shrinking below 1.0 keeps the
          // HUD honest on phones that ask for smaller text.
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(MediaQuery.of(context).textScaler.scale(1.0).clamp(1.0, 1.3)),
          ),
          child: AppLifecycleHost(child: UpdateGate(child: ProgressWatcher(child: child ?? const SizedBox()))),
        ),
      ),
      home: auth.signedIn ? const HomeShell() : const LoginScreen(),
    );
  }
}
