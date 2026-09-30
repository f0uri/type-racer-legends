import 'package:cloud_functions/cloud_functions.dart';
import '../../data/models/profile.dart';
import '../../data/remote/cloud_sync.dart';
import '../../data/remote/firebase_boot.dart';

class ReferralResult {
  final bool ok;
  final String message;
  final int coins, gems, invitees;
  const ReferralResult(this.ok, this.message, {this.coins = 0, this.gems = 0, this.invitees = 0});
}

/// Friend-invite rewards. The Cloud Functions hold the one-time flags; the app applies the rewards.
class ReferralService {
  ReferralService(this.cloud);
  final CloudSync cloud;

  static const redeemedFlag = 'ref_redeemed';

  static String _error(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'not-found':
        return 'هذا الرمز غير موجود';
      case 'already-exists':
        return 'سبق أن استخدمت رمز دعوة';
      case 'failed-precondition':
        return e.message == 'own code' ? 'لا يمكنك استخدام رمزك الخاص' : 'زامن حسابك أولاً ثم أعد المحاولة';
      case 'invalid-argument':
        return 'الرمز غير صالح';
      case 'unauthenticated':
        return 'سجّل الدخول بحساب جوجل أولاً';
      case 'resource-exhausted':
        return 'محاولات كثيرة، انتظر قليلاً';
      default:
        return 'تعذّر الاتصال بالخادم، حاول لاحقاً';
    }
  }

  /// The new player enters a friend's code.
  Future<ReferralResult> redeem(String code) async {
    if (!FirebaseBoot.available || cloud.uid == null) return const ReferralResult(false, 'سجّل الدخول بحساب جوجل لاستخدام الدعوات');
    try {
      await cloud.callFn<dynamic>('redeemReferral', {'code': code.trim().toUpperCase()});
      return const ReferralResult(true, 'تم تسجيل الرمز! ستصلك المكافأة عند بلوغ المستوى 5.');
    } on FirebaseFunctionsException catch (e) {
      return ReferralResult(false, _error(e));
    } catch (_) {
      return const ReferralResult(false, 'تعذّر الاتصال بالخادم، حاول لاحقاً');
    }
  }

  /// Asks the server what can be collected now (as invitee and as inviter).
  Future<ReferralResult> claim() async {
    if (!FirebaseBoot.available || cloud.uid == null) return const ReferralResult(false, 'سجّل الدخول بحساب جوجل أولاً');
    try {
      final r = await cloud.callFn<Map<dynamic, dynamic>>('claimReferralRewards', const {});
      final coins = (r?['coins'] as num?)?.toInt() ?? 0, gems = (r?['gems'] as num?)?.toInt() ?? 0, n = (r?['invitees'] as num?)?.toInt() ?? 0;
      if (coins == 0 && gems == 0) return const ReferralResult(true, 'لا توجد مكافآت جاهزة الآن.');
      return ReferralResult(true, 'استلمت $coins عملة و$gems جوهرة 🎉', coins: coins, gems: gems, invitees: n);
    } on FirebaseFunctionsException catch (e) {
      return ReferralResult(false, _error(e));
    } catch (_) {
      return const ReferralResult(false, 'تعذّر الاتصال بالخادم، حاول لاحقاً');
    }
  }

  static void apply(PlayerProfile p, ReferralResult r) {
    if (r.coins > 0) p.addCoins(r.coins);
    if (r.gems > 0) p.addGems(r.gems);
    if (r.invitees > 0) p.addCounter('ref_invites', r.invitees);
  }
}
