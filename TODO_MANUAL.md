# الخطوات اليدوية (بالترتيب)

كل ما يمكن أتمتته تمّ داخل المستودع. ما يلي يحتاج حساباتك أنت ولا يمكن تنفيذه من الكود. **اللعبة تعمل بدونها** كزائر/Offline؛ كل خطوة تفتح ميزة إضافية.

## 0. أمان أولاً
1. **اسحب (Revoke) كل رموز GitHub (Personal Access Tokens)** التي لصقتها في المحادثة: GitHub → Settings → Developer settings → Personal access tokens. أنشئ رمزاً جديداً فقط إن احتجت.

## 1. مشروع Firebase (يفعّل الحسابات والمزامنة واللوحات والإشعارات)
1. أنشئ مشروعاً في https://console.firebase.google.com وفعّل **Google Analytics**.
2. أضف تطبيق **Android** باسم الحزمة `com.typeracerlegends.game`.
3. **قبل تنزيل الملف**: Authentication → Sign-in method → فعّل **Google**؛ ثم في Project settings → تطبيقك → أضف بصمات **SHA-1** و**SHA-256**:
   - بصمة مفتاح النشر (Keystore) — أنشئه في الخطوة 6 (`keytool -list -v -keystore release.jks`).
   - بصمة debug إن أردت التجربة من APK الـCI (`keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`).
   - إن رفعت التطبيق إلى Play: بصمة **App signing key** من Play Console → App integrity.
4. نزّل `google-services.json` (يجب أن يحوي عميل OAuth من النوع Web، وإلا فشل تسجيل جوجل).
5. فعّل **Firestore** (وضع Production) و**Cloud Functions** (يتطلب خطة Blaze) و**Remote Config** و**Cloud Messaging** و**Crashlytics**.
6. لا تفعّل Realtime Database (غير مستخدمة).

## 2. أسرار GitHub (Settings → Secrets and variables → Actions)
| السر | القيمة |
|---|---|
| `GOOGLE_SERVICES_JSON` | محتوى `google-services.json` كاملاً (نص) |
| `KEYSTORE_BASE64` | `base64 -w0 release.jks` |
| `KEY_ALIAS` / `KEY_PASSWORD` / `STORE_PASSWORD` | بيانات الـKeystore |
| `ADMOB_APP_ID` | معرّف تطبيق AdMob (اختياري؛ الافتراضي تجريبي) |
| `ADMOB_REWARDED_ID` / `ADMOB_INTERSTITIAL_ID` | معرّفات الوحدات الإعلانية (اختياري) |

بعد الإضافة: Actions → Build → **Run workflow** (أو ادفع أي commit).

## 3. نشر Cloud Functions وقواعد Firestore
```bash
npm i -g firebase-tools && firebase login
firebase use --add                 # اختر مشروعك
cd functions && npm install && cd ..
firebase deploy --only functions,firestore:rules,firestore:indexes
```
المنطقة `europe-west1` (مطابقة لـ`AppConfig.functionsRegion`؛ غيّرهما معاً إن أردت منطقة أخرى).
بعد أول نشر أنشئ مستند `config/limits` (اختياري) لتعديل حدود مكافحة الغش، وراجع سجلات الدوال.

## 4. التحقق من المشتريات (verifyPurchase)
الدالة تستخدم Application Default Credentials، أي **حساب الخدمة الذي تعمل به الدالة** (الافتراضي: `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`، أو أي حساب خدمة تحدده للدالة).
1. فعّل **Google Play Android Developer API** في مشروع Google Cloud المرتبط بـFirebase.
2. Play Console → Users and permissions → **Invite new users** → ضع بريد حساب الخدمة أعلاه وامنحه صلاحيتي **View financial data** و**Manage orders and subscriptions**.
3. لا حاجة لمفتاح JSON ولا لتعديل الكود. (إن أردت حساب خدمة مخصصاً: `serviceAccount` في خيارات الدالة.)
إلى أن يتم ذلك: الدالة تُرجع `valid: null` والتطبيق يسلّم المشترى مؤقتاً على الجهاز.

## 5. Google Play Console
1. أنشئ التطبيق (اسم الحزمة `com.typeracerlegends.game`) وأكمل بطاقة المتجر ومحتوى التطبيق (Data safety: Analytics/Crashlytics، AdMob، حساب جوجل).
2. **المنتجات داخل التطبيق** (بالمعرّفات نفسها تماماً):
   - `remove_ads` (غير قابل للاستهلاك)
   - `battle_pass_premium` (غير قابل للاستهلاك)
   - `gems_small` و`gems_medium` و`gems_large` (قابلة للاستهلاك)
3. ارفع **AAB** من Release → Internal testing أولاً. فعّل **Play App Signing**.
4. أضف رابط **سياسة الخصوصية** (صفحة خارجية) — النص موجود داخل التطبيق في `lib/features/settings/legal_texts.dart`؛ يمكنك نشره على `site/` ثم ضبط `PRIVACY_URL`.

## 6. مفتاح التوقيع (Keystore)
```bash
keytool -genkeypair -v -keystore release.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 release.jks   # ← قيمة KEYSTORE_BASE64
```
احتفظ بنسخة احتياطية آمنة من الملف وكلمات المرور (فقدانه يمنع تحديث التطبيق).

## 7. AdMob
1. أنشئ تطبيقاً في https://admob.google.com وأنشئ وحدتين: **Rewarded** و**Interstitial**.
2. ضع المعرّفات في أسرار GitHub (الخطوة 2). لا تستعمل معرّفات حقيقية أثناء التطوير (استعمل أجهزة اختبار).
3. اضبط رسالة الموافقة (UMP/GDPR) من AdMob → Privacy & messaging.

## 8. Remote Config (اختياري، للضبط بدون تحديث)
أنشئ المفاتيح: `kill_features` (قائمة مفصولة بفواصل)، `kill_items`، `kill_switch`، `min_supported_version`، `daily_coin_cap`، `interstitial_every_n`، `interstitial_enabled`، `rewarded_daily_limit`، `maintenance_message`. ثم Publish.

## 9. الإشعارات (FCM)
- تذكير السلسلة والأحداث محلية وتعمل فوراً.
- للإعلان من الخادم: في Firestore أنشئ/عدّل المستند `config/announcement` بالحقول `{ id, title, body, topic }` (`topic` = `events` أو `all`) فتُرسل الدالة `onAnnouncement` إشعاراً. غيّر `id` لكل إعلان جديد.

## 10. GitHub Pages
Settings → Pages → Source: **GitHub Actions**. أول تشغيل لـ**Publish live content** ينشر المحتوى على
`https://f0uri.github.io/type-racer-legends/` (المحتوى، `version.json`، وصفحة روابط التحدي `/c/`).
إن غيّرت اسم المستودع أو المستخدم فحدّث `AppConfig` (`contentBaseUrl`, `updateJsonUrl`, `challengeLandingUrl`) ومرشّح الـintent في `AndroidManifest.xml`.

## 11. الإصدار الأول
```bash
git tag v1.0.0 && git push origin v1.0.0
```
ينتج Release فيه APK + AAB و`version.json`. (الوسم `v1.0.0` أُنشئ بالفعل إن كان ظاهراً في صفحة Releases.)

## 12. مراجعات أخيرة قبل النشر العام
- جرّب على جهاز حقيقي: تسجيل جوجل، المزامنة، الشراء (حساب اختبار ترخيص)، الإعلانات (معرّفات تجريبية)، الإشعارات (Android 13+ يطلب الإذن)، الودجت (اضغط مطولاً على الشاشة الرئيسية → Widgets).
- أضف ترجمة/نصوص إسبانية إن أردت (`content/texts/` بنفس الشكل) وفعّلها من الإعدادات.
- راجع نص سياسة الخصوصية والشروط مع مستشار قانوني قبل الإطلاق العام.
