import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'features/lifecycle/app_lifecycle.dart';

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
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: AppLifecycleHost(child: child ?? const SizedBox()),
        ),
      ),
      home: auth.signedIn ? const HomeShell() : const LoginScreen(),
    );
  }
}
