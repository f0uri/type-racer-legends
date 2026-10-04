import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/providers.dart';
import '../../data/remote/drive_sync.dart';
import '../../data/remote/firebase_boot.dart';
import '../../data/remote/progress_sync.dart';

class AuthState {
  final String mode; // none | guest | google
  final String? email, displayName, photoUrl;
  final bool busy;

  /// Short-lived Google access token for the `drive.appdata` scope, when the player granted it.
  /// Never persisted: it is re-acquired silently on demand (see [AuthController.refreshDriveToken]).
  final String? driveToken;
  const AuthState({this.mode = 'none', this.email, this.displayName, this.photoUrl, this.busy = false, this.driveToken});
  bool get signedIn => mode != 'none';
  bool get isGoogle => mode == 'google';
  bool get driveReady => driveToken != null;
  AuthState copyWith({String? mode, String? email, String? displayName, String? photoUrl, bool? busy, String? driveToken}) =>
      AuthState(mode: mode ?? this.mode, email: email ?? this.email, displayName: displayName ?? this.displayName, photoUrl: photoUrl ?? this.photoUrl, busy: busy ?? this.busy, driveToken: driveToken ?? this.driveToken);
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
    if (e is GoogleSignInException) {
      switch (e.code) {
        case GoogleSignInExceptionCode.canceled:
        case GoogleSignInExceptionCode.interrupted:
          return 'تم إلغاء تسجيل الدخول.';
        case GoogleSignInExceptionCode.clientConfigurationError:
        case GoogleSignInExceptionCode.providerConfigurationError:
          return 'إعدادات تسجيل الدخول غير مكتملة في هذه النسخة. يمكنك المتابعة كزائر.';
        case GoogleSignInExceptionCode.uiUnavailable:
          return 'تعذّر فتح نافذة اختيار الحساب. حاول مرة أخرى.';
        default:
          return 'تعذّر تسجيل الدخول بجوجل. حاول مرة أخرى.';
      }
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'network-request-failed':
          return 'فشل الاتصال بالشبكة. تحقق من الإنترنت وحاول مجدداً.';
        case 'user-disabled':
          return 'تم تعطيل هذا الحساب.';
        case 'account-exists-with-different-credential':
          return 'هذا البريد مرتبط بطريقة دخول أخرى.';
        case 'too-many-requests':
          return 'محاولات كثيرة. انتظر قليلاً ثم حاول مجدداً.';
        case 'requires-recent-login':
          return 'لأسباب أمنية، سجّل الدخول مرة أخرى ثم أعد المحاولة.';
        default:
          return 'حدث خطأ أثناء تسجيل الدخول (${e.code}).';
      }
    }
    if (e is FirebaseException) return 'حدث خطأ في الخدمة (${e.code}).';
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

  /// The Web OAuth client id (build define or `assets/google_client_id.txt`).
  /// On Android this is what makes `authentication.idToken` non-null and what lets us ask for
  /// extra scopes (Drive) without a second consent screen of a different client type.
  String get _webClientId => googleWebClientId;

  Future<GoogleSignInAccount> _pickAccount() async {
    if (!_gsiReady) {
      await GoogleSignIn.instance.initialize(
        clientId: _webClientId.isEmpty ? null : _webClientId,
        serverClientId: _webClientId.isEmpty ? null : _webClientId,
      );
      _gsiReady = true;
    }
    return GoogleSignIn.instance.authenticate();
  }

  /// Asks Google for an access token carrying the Drive app-folder scope (google_sign_in 7.2.0).
  ///
  /// Set [interactive] to allow a consent prompt; otherwise only an already-granted (or
  /// silently refreshable) token is returned. Anything that goes wrong here — the player
  /// declining the scope, no network, an old plugin — must never break sign-in itself, so the
  /// failure is swallowed and Drive sync simply stays off.
  Future<String?> _driveTokenFrom(GoogleSignInAccount? account, {bool interactive = false}) async {
    if (account == null) return null;
    try {
      final client = account.authorizationClient;
      // Returns null when the grant cannot be reused without showing UI again.
      GoogleSignInClientAuthorization? granted =
          await client.authorizationForScopes(const [DriveSync.scope]);
      if (granted == null && interactive) {
        granted = await client.authorizeScopes(const [DriveSync.scope]);
      }
      final value = granted?.accessToken;
      if (value != null && value.isNotEmpty) {
        await ref.read(storeProvider).meta.put('driveScopeGranted', true);
        return value;
      }
      return null;
    } catch (e) {
      debugPrint('drive authorization unavailable: $e');
      return null;
    }
  }

  /// Returns a Drive access token, re-authorizing silently (or interactively when asked).
  Future<String?> refreshDriveToken({bool interactive = false}) async {
    if (!FirebaseBoot.available || !state.isGoogle) return null;
    try {
      final account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      final token = await _driveTokenFrom(account, interactive: interactive);
      if (token != null) state = state.copyWith(driveToken: token);
      return token;
    } catch (e) {
      debugPrint('drive token refresh failed: $e');
      return null;
    }
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
      final drive = await _driveTokenFrom(account, interactive: true);
      if (drive != null) state = state.copyWith(driveToken: drive);
      await ref.read(profileProvider.notifier).linkAccount(u.uid, displayName: u.displayName);
      // A device that has never synced pulls the player's save out of their own Drive and merges
      // it: same account on a new phone means the same level, wallet, garage and settings.
      if (drive != null) {
        final restored = await ref.read(progressSyncProvider.notifier).pullAndMerge();
        if (restored) ref.read(progressSyncProvider.notifier).schedule(const Duration(seconds: 3));
      }
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
      // The save stays in the player's Drive; the token dies with the session.
      ref.read(progressSyncProvider.notifier).forget();
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
        // Take the cloud save with it: the player asked for their data to be gone.
        await ref.read(progressSyncProvider.notifier).eraseRemote();
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
