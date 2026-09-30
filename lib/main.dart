import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/providers.dart';
import 'data/local/local_store.dart';
import 'data/remote/firebase_boot.dart';
import 'features/content/content_repository.dart';
import 'features/notifications/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light, systemNavigationBarColor: Color(0xFF0B0F1E)));
  final store = await LocalStore.init();
  await FirebaseBoot.init();
  if (FirebaseBoot.available) FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  final content = await ContentRepository(store).loadLocal();
  runApp(ProviderScope(
    overrides: [storeProvider.overrideWithValue(store), initialContentProvider.overrideWithValue(content)],
    child: const TypeRacerApp(),
  ));
}
