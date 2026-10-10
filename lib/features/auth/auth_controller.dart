import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/providers.dart';
import '../../data/remote/firebase_boot.dart';

class AuthState {
  final String mode; // none | guest | google
  final String? email, displayName, photoUrl;
  final bool busy;
  const AuthState({this.mode = 'none', this.email, this.displayName, this.photoUrl, this.busy = false});
  bool get signedIn => mode != 'none';
  bool get isGoogle => mode == 'google';
  AuthState copyWith({String? mode, String? email, String? displayName, String? photoUrl, bool? busy}) =>
      AuthState(mode: mode ?? this.mode, email: email ?? this.email, displayName: displayName ?? this.displayName, photoUrl: photoUrl ?? this.photoUrl, busy: busy ?? this.busy);
}

class AuthController extends Notifier<AuthState> {
  static bool _gsiReady = false;
  StreamSubscription<User?>? _sub;

  @override
  AuthState build() {
    ref.onDispose(() => _sub?.cancel());
    final store = ref.read(storeProvider);
    if (FirebaseBoot.available) {
      final u = FirebaseAuth.instance.currentUser;
      _sub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user == null && state.mode == 'google') {
          // Session revoked/expired remotely: keep local progress as guest.
          store.authMode = 'guest';
          state = const AuthState(mode: 'guest');
        }
      });
      if (u != null) {
        store.authMode = 'google';
        return AuthState(mode: 'google', email: u.email, displayName: u.displayName, photoUrl: u.photoURL);
      }
    }
    final mode = store.authMode;
    if (mode == 'google') {
      // Was signed in earlier but Firebase unavailable right now: stay in offline session.
      return const AuthState(mode: 'guest');
    }
    return AuthState(mode: mode ?? 'none');
  }

  Future<void> continueAsGuest() async {
    ref.read(storeProvider).authMode = 'guest';
    await ref.read(storeProvider).saveProfile(ref.read(profileProvider));
    state = const AuthState(mode: 'guest');
  }

  static String messageForError(Object e) {
    final raw = e.toString();
    final lower = raw.toLowerCase();

    // --- أسباب حقيقية من ApiException (تظهر في google_sign_in / Play Services) ---
    // 12500 = SIGN_IN_FAILED / إعداد Firebase ناقص (غالباً بدون عميل Web)
    if (raw.contains('12500')) {
      return 'فشل تسجيل الدخول (12500): إعداد Firebase ناقص. ملف google-services.json لا يحوي عميل OAuth من النوع Web (client_type 3). في Firebase Console فعّل Authentication → Google، ثم نزّل google-services.json من جديد وحدّثه في GitHub → Settings → Secrets → GOOGLE_SERVICES_JSON.';
    }
    // 10 = DEVELOPER_ERROR = بصمة SHA-1 غير مسجّلة
    // يظهر كـ ApiException: 10 أو DEVELOPER_ERROR داخل GoogleSignInException
    final isApi10 = raw.contains('ApiException: 10') ||
        raw.contains('DEVELOPER_ERROR') ||
        (lower.contains('apiexception') && RegExp(r'\b10\b').hasMatch(raw) && !raw.contains('12500'));
    if (isApi10) {
      // تحقق إضافي لتجنب الإيجابيات الكاذبة: إذا احتوى نفس النص على 10 بشكل عام لكنه ApiException حقيقي
      if (raw.contains('10:') || raw.contains('10 ') || raw.contains('(10)') || lower.contains('apiexception') || raw.contains('DEVELOPER_ERROR')) {
        return 'فشل تسجيل الدخول (رمز 10): بصمة SHA-1 غير مسجّلة في Firebase. افتح ملخص البناء (Job Summary) وانسخ بصمتي SHA-1 و SHA-256 لمفتاح debug الثابت (tools/ci-debug.keystore)، ثم أضفهما في Firebase Console → Project settings → تطبيق Android، ونزّل google-services.json الجديد وحدّث سر GitHub GOOGLE_SERVICES_JSON.';
      }
    }
    // 7 = NETWORK_ERROR = لا إنترنت
    if (raw.contains('ApiException: 7') || raw.contains('NETWORK_ERROR') || (lower.contains('apiexception') && lower.contains('network') && RegExp(r'\b7\b').hasMatch(raw))) {
      return 'لا يوجد اتصال بالإنترنت (رمز 7). تحقّق من الشبكة وحاول مجدداً.';
    }

    if (e is GoogleSignInException) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return 'تم إلغاء تسجيل الدخول.';
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          // قد يكون السبب الحقيقي 10 أو 12500 مغلف داخل التفاصيل
          if (raw.contains('12500')) {
            return 'فشل تسجيل الدخول (12500): إعداد Firebase ناقص. ملف google-services.json لا يحوي عميل OAuth من النوع Web (client_type 3). فعّل Google في Authentication ونزّل الملف من جديد.';
          }
          if (raw.contains('10') || raw.contains('DEVELOPER_ERROR')) {
            return 'فشل تسجيل الدخول (رمز 10): بصمة SHA-1 غير مسجّلة في Firebase. أضف بصمتي SHA-1 و SHA-256 من ملخص البناء إلى Project settings.';
          }
          return 'إعدادات تسجيل الدخول غير مكتملة في هذه النسخة. تأكد من إضافة بصمتي SHA-1 و SHA-256 في Firebase وتحديث google-services.json (قد يكون السبب 10 أو 12500). يمكنك المتابعة كزائر مؤقتاً.';
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'تعذّر فتح نافذة اختيار الحساب. حاول مرة أخرى.';
        default:
          if (lower.contains('network') || lower.contains('socket') || lower.contains('connection')) {
            return 'لا يوجد اتصال بالإنترنت (رمز 7). تحقّق من الشبكة وحاول مجدداً.';
          }
          // إظهار السبب الحقيقي إن كان مخفياً في النص
          if (raw.contains('10')) {
            return 'فشل تسجيل الدخول (رمز 10): بصمة SHA-1 غير مسجّلة في Firebase. راجع ملخص البناء لإضافة البصمات.';
          }
          return 'تعذّر تسجيل الدخول بجوجل. حاول مرة أخرى.';
      }
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'network-request-failed':
          return 'فشل الاتصال بالشبكة. تحقق من الإنترنت وحاول مجدداً. (رمز 7)';
        case 'user-disabled':
          return 'تم تعطيل هذا الحساب.';
        case 'account-exists-with-different-credential':
          return 'هذا البريد مرتبط بطريقة دخول أخرى.';
        case 'too-many-requests':
          return 'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.';
        case 'requires-recent-login':
          return 'لأسباب أمنية، سجّل الدخول مرة أخرى ثم أعد المحاولة.';
        default:
          if (raw.contains('10')) return 'فشل تسجيل الدخول (رمز 10): بصمة SHA-1 غير مسجّلة في Firebase. راجع ملخص البناء لإضافة البصمات.';
          if (raw.contains('12500')) return 'فشل تسجيل الدخول (12500): إعداد Firebase ناقص — google-services.json بدون عميل Web.';
          if (lower.contains('network')) return 'لا يوجد اتصال بالإنترنت (رمز 7). تحقّق من الشبكة وحاول مجدداً.';
          return 'حدث خطأ أثناء تسجيل الدخول (${e.code}).';
      }
    }
    if (e is FirebaseException) {
      if (lower.contains('network')) return 'لا يوجد اتصال بالإنترنت (رمز 7). تحقّق من الشبكة وحاول مجدداً.';
      return 'حدث خطأ في الخدمة (${e.code}).';
    }
    // شبكة عامة (ApiException 7 بدون تغليف)
    if (lower.contains('network') || lower.contains('socket') || lower.contains('failed host lookup') || lower.contains('connection timed out') || lower.contains('unable to resolve host')) {
      return 'لا يوجد اتصال بالإنترنت (رمز 7). تحقّق من الشبكة وحاول مجدداً.';
    }
    return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
  }

  Future<bool> _hasNetwork() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return !r.contains(ConnectivityResult.none) || r.length > 1;
    } catch (_) {
      return true;
    }
  }

  Future<GoogleSignInAccount> _pickAccount() async {
    if (!_gsiReady) {
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '604615848597-tt64km06nj5adqqifdvmcijbqrbgqnoh.apps.googleusercontent.com',
      );
      _gsiReady = true;
    }
    return GoogleSignIn.instance.authenticate();
  }

  /// Opens the native Android account picker (Credential Manager) and signs in to Firebase.
  /// Returns an Arabic error message, or null on success.
  Future<String?> signInWithGoogle() async {
    if (!FirebaseBoot.available) {
      return 'تسجيل الدخول غير متاح في هذه النسخة (Firebase غير مُعدّ). يمكنك المتابعة كزائر.';
    }
    if (!await _hasNetwork()) return 'لا يوجد اتصال بالإنترنت. تسجيل الدخول يحتاج إلى اتصال.';
    state = state.copyWith(busy: true);
    try {
      final account = await _pickAccount();
      final idToken = account.authentication.idToken;
      if (idToken == null) return 'لم نتمكن من الحصول على بيانات الحساب. حاول مجدداً.';
      final cred = GoogleAuthProvider.credential(idToken: idToken);
      final res = await FirebaseAuth.instance.signInWithCredential(cred);
      final u = res.user!;
      ref.read(storeProvider).authMode = 'google';
      state = AuthState(mode: 'google', email: u.email, displayName: u.displayName, photoUrl: u.photoURL);
      await ref.read(profileProvider.notifier).linkAccount(u.uid, displayName: u.displayName);
      return null;
    } catch (e, st) {
      if (!(e is GoogleSignInException && e.code == GoogleSignInExceptionCode.canceled)) FirebaseBoot.log('google sign-in failed', e, st);
      return messageForError(e);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Signs out. Progress is synced first; the local copy is archived, never silently destroyed.
  Future<String?> signOut() async {
    state = state.copyWith(busy: true);
    try {
      final synced = await ref.read(profileProvider.notifier).syncNow();
      if (!synced && FirebaseBoot.available && ref.read(cloudSyncProvider).uid != null) {
        debugPrint('signing out with unsynced progress (archived locally)');
      }
      try {
        if (_gsiReady) await GoogleSignIn.instance.signOut();
      } catch (_) {}
      if (FirebaseBoot.available) await FirebaseAuth.instance.signOut();
      await ref.read(profileProvider.notifier).resetToFresh();
      ref.read(storeProvider).authMode = null;
      state = const AuthState(mode: 'none');
      return null;
    } catch (e) {
      return messageForError(e);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// Deletes server data + auth account, then wipes everything local.
  Future<String?> deleteAccount() async {
    state = state.copyWith(busy: true);
    try {
      if (FirebaseBoot.available && FirebaseAuth.instance.currentUser != null) {
        if (!await _hasNetwork()) return 'حذف الحساب يحتاج إلى اتصال بالإنترنت.';
        try {
          await ref.read(cloudSyncProvider).callFn<dynamic>('deleteAccountData', {});
        } catch (e) {
          debugPrint('deleteAccountData failed: $e');
        }
        try {
          await FirebaseAuth.instance.currentUser!.delete();
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            final account = await _pickAccount();
            final cred = GoogleAuthProvider.credential(idToken: account.authentication.idToken);
            await FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(cred);
            await FirebaseAuth.instance.currentUser!.delete();
          } else {
            rethrow;
          }
        }
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
      await ref.read(storeProvider).wipeEverything();
      await ref.read(profileProvider.notifier).resetToFresh();
      await ref.read(storeProvider).wipeEverything();
      state = const AuthState(mode: 'none');
      return null;
    } catch (e, st) {
      FirebaseBoot.log('delete account failed', e, st);
      return messageForError(e);
    } finally {
      state = state.copyWith(busy: false);
    }
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
