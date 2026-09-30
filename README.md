# 🏎️ Type Racer Legends

لعبة سباقات كتابة (إنجليزي + وضع فرنسي) بالسيارات والدراجات النارية، مبنية بـ **Flutter + Flame + Riverpod**.
**كل السباقات ضد منافسين بالذكاء الاصطناعي فقط** — لا يوجد لاعبون حقيقيون، واللعبة لا تدّعي ذلك في أي شاشة
(كل منافس يحمل شارة `AI`). الواجهة عربية RTL، الاتجاه عمودي، الحد الأدنى Android 7 (API 24).

> اللعبة تعمل كاملةً **كزائر وبدون إنترنت وبدون Firebase**. عند إضافة `google-services.json` تُفعَّل الحسابات والمزامنة
> واللوحات والإشعارات تلقائياً. الخطوات اليدوية المطلوبة منك موجودة بالترتيب في [`TODO_MANUAL.md`](TODO_MANUAL.md).

## المزايا

| المجال | ما هو موجود |
|---|---|
| **الأوضاع (11)** | الحملة (50 مرحلة، 6 بيئات، زعيم لكل بيئة مع تحدّيات كلامية) • السباق السريع (3–7 منافسين) • الأشباح (شبحك الشخصي + أشباح AI) • بطولات AI (8/16، يومية/أسبوعية) • تحدٍّ برابط (Deep Link ضد شبح AI) • البقاء • قتال الطريق • التحدي اليومي/الأسبوعي • جولة العالم (12 مدينة) • التدريب الذكي (خريطة حرارية للحروف الضعيفة) • نص مخصص |
| **الذكاء الاصطناعي** | WPM أساسي مع تباين طبيعي وأخطاء، 4 شخصيات، rubber-banding مخفي، أسماء وأعلام واقعية، تعليقات قصيرة (دائماً موسومة AI) |
| **داخل السباق** | محطة صيانة (Pit Stop) • كلمات القوة SHIELD / EMP / TURBO • مضاعف مخاطرة x2 • Slipstream • نيترو (لهب، ضبابية، خطوط سرعة، FOV) • كلمة مثالية • Photo Finish مع إعادة بطيئة • كومبو x2+ • اهتزاز لمسي • كاميرا ديناميكية • Pool للجسيمات |
| **البيئات** | ضباب، جليد (تبديل حروف)، انقطاع إضاءة، عاصفة (اهتزاز) + مرئيات مطر/ثلج/غبار |
| **المحتوى** | 600+ نص (إنجليزي + مكتبة فرنسية، قابلة لإضافة الإسبانية) من الملكية العامة أو أصلية • 287 كلمة مفردات • 30 درس • كل شيء JSON |
| **التعلّم** | مفردات عربي→إنجليزي، 30 درس لمس مع خريطة الأصابع، اختبار تحديد المستوى، هدف أسبوعي شخصي، اختبار رسمي 60 ثانية + **شهادة WPM قابلة للمشاركة (PDF/PNG)** |
| **المركبات** | 25 مركبة (سيارات + دراجات) مرسومة برمجياً، 3 ندرات، 4 ترقيات (تسارع/ثبات/نيترو/أرباح)، تخصيص كامل (لون، طلاء، جنوط، إضاءة سفلية، عادم، لهب النيترو، ملصقات، لوحة، بوق، احتفال)، عرض 360° في الكراج |
| **التقدّم** | XP ومستويات • تصنيف برونزي→أسطورة • مواسم 4 أسابيع + Battle Pass • مهام يومية/أسبوعية • سلسلة دخول يومية • صناديق متحركة بنسب شفافة • 90 إنجازاً مع ألقاب • لوحات متصدرين (عالمي/دولة/أسبوعي/شهري) بتحقق من الخادم • دعوة الأصدقاء • أحداث موسمية (رمضان، كأس العالم، العودة للمدارس) |
| **المشاركة** | بطاقة اللاعب وصورة الفوز (PNG) • رابط تحدٍّ • شهادة |
| **الاقتصاد** | عملات وجواهر، سقف يومي للعملات مع حدّ أدنى مضمون للمجانيين • إعلانات مكافأة **اختيارية** فقط + إعلان بيني نادر بين السباقات (تردد قابل للضبط عن بُعد، ولا يظهر أبداً أثناء سباق) • شراء: إزالة الإعلانات، حزم جواهر، Battle Pass • **لا قمار** (احتمالات الصناديق معروضة وتُشترى بعملات اللعبة فقط) |
| **المحتوى الحي** | `content/*.json` تُنشر على GitHub Pages، جلب بـ ETag، كاش Hive، شارة «جديد»، فحص مخطط وhash، لا كود قابل للتنفيذ، مفتاح إيقاف عن بُعد |
| **التحديث** | Google Play (`in_app_update` مرن/فوري) + APK خارج المتجر عبر `version.json` (تنزيل بتقدم، إلغاء، استئناف، SHA-256، تثبيت، تحذير بيانات الجوال، شرح صلاحية التثبيت) • إلزامي بشاشة كاملة، واختياري يؤجَّل يوماً |
| **مكافحة الغش** | Cloud Functions تتحقق من حدود WPM وفواصل الضغط؛ النتائج المشبوهة تُستبعد من اللوحات |
| **الإعدادات وإمكانية الوصول** | صوت/موسيقى، اهتزاز، حجم الخط، خط لعسر القراءة (OpenDyslexic)، عمى الألوان، صعوبة النصوص، تلميح الحرف التالي، تعطيل Backspace، وضع 30 إطاراً، تنبيه استراحة، شرح تفاعلي، سياسة الخصوصية والشروط والتراخيص داخل التطبيق |
| **الإشعارات والودجت** | تذكير السلسلة قبل انتهائها بساعتين، تنبيهات الأحداث، FCM (مواضيع + إعلانات)، ودجت أندرويد (السلسلة + أفضل WPM) |

## بنية المشروع

```
lib/
  core/        الثيم، الويدجت المشتركة، الصوت (مولّد برمجياً)، الاهتزاز، التحليلات، الإعدادات عن بُعد
  data/        models (Profile, Content) • local (Hive) • merge (دمج التقدّم) • remote (Firestore/Functions)
  features/
    auth/ race/ ai/ career/ garage/ leaderboard/ shop/ stats/ learn/
    content/ update/ settings/ profile/ notifications/ widget/ ads/ tutorial/ home/ lifecycle/
functions/     Cloud Functions (Node 20): submitScore, verifyPurchase, referrals, backups, حذف الحساب، إعلانات FCM
firestore.rules  قواعد الأمان لكل مستخدم
content/       بذرة المحتوى الحي (JSON) + catalog.json
tools/         مولّدات المحتوى والفهرس وversion.json
site/          صفحة GitHub Pages (صفحة هبوط روابط التحدي)
.github/workflows/  build.yml • pages.yml • release.yml
```

**المزامنة:** Offline-first على Hive. الأرقام التراكمية (عملات، XP، إحصاءات) عدّادات لكل جهاز تُجمع عند الدمج فلا يضيع تقدّم ولا يتضاعف؛
بقية الحقول تُدمج بـ `updatedAt` مع رقم نسخة، ويكتب الخادم داخل Firestore Transaction. تُجرى المزامنة عند عودة الشبكة، نهاية السباق، والذهاب للخلفية.
عند ربط حساب جوجل يُدمج تقدّم الزائر بذكاء مع تقدّم الحساب.

## التشغيل محلياً

```bash
flutter pub get
flutter run                      # يعمل كزائر/Offline بدون أي إعداد
flutter analyze && flutter test  # 200 اختبار (WPM، الدمج، المزامنة، الـAI، الاقتصاد، الواجهات...)
node --test functions/test/*.test.js   # اختبارات مكافحة الغش
```

متغيرات اختيارية عبر `--dart-define`: `ADMOB_REWARDED_ID`, `ADMOB_INTERSTITIAL_ID` (الافتراضي معرّفات اختبار Google),
`CONTENT_BASE_URL`, `UPDATE_JSON_URL`, `CHALLENGE_URL`, `PRIVACY_URL`, `GITHUB_REPO`.
لتفعيل Firebase ضع `google-services.json` في `android/app/` (انظر `TODO_MANUAL.md`).

## إضافة محتوى بدون تحديث التطبيق

كل تعديل في `content/` يُنشر تلقائياً عند دفعه إلى `main` (workflow **Publish live content**): يتحقق من صحة JSON، يعيد بناء `catalog.json` (hash + رقم إصدار لكل ملف) وينشر على GitHub Pages. التطبيق يجلب الفهرس بـ ETag ويتحقق من المخطط والـhash قبل القبول.

### إضافة Skin
أضف عنصراً في `content/skins.json` (مصفوفة `items`):

```json
{ "id": "p_sunset", "type": "skin", "slot": "paint",
  "name": { "ar": "غروب", "en": "Sunset", "fr": "Coucher de soleil" },
  "rarity": "rare", "price": { "coins": 4000 }, "unlock": {}, "enabled": true,
  "startsAt": null, "endsAt": null, "kinds": ["car", "bike"], "tags": [],
  "params": { "pattern": "gradient", "colors": ["#ff7b00", "#ff006e"] } }
```
`slot`: `paint | rims | underglow | exhaust | nitro | sticker | horn | celebration | plate`. `rarity`: `common | rare | legendary`.
اجعل `enabled: false` لإخفائه، أو أضف `startsAt/endsAt` لعرضه لفترة محدودة. لإبراز عناصر في المتجر أضفها إلى `featured.shop` في `catalog.json`.

### إضافة حدث موسمي
أضف عنصراً في `content/events.json` (انسخ `back_to_school_2026`): `id`، `name`، `desc`، `startsAt`/`endsAt` (ISO UTC)، `color`، `xpMultiplier`،
`featured` (عناصر مميزة)، `tasks` (كل مهمة: `id`، `metric`، `target`، `reward`) و`finalReward`. تُجدول الإشعارات المحلية للحدث تلقائياً (بداية الحدث ويوم قبل نهايته).

### مفتاح الإيقاف عن بُعد
في `content/catalog.json` → `killSwitch`: `features` (من: `ads, iap, tournament, daily, link_challenge, leaderboard, survival, combat, world_tour, shop, updates`) و`items` (معرّفات عناصر). أو عبر Firebase Remote Config: `kill_features`, `kill_items`, `daily_coin_cap`, `interstitial_every_n`, `interstitial_enabled`, `rewarded_daily_limit`, `min_supported_version`, `maintenance_message`.

### إضافة نصوص
ضع الملفات في `content/texts/` (مصفوفة نصوص `{id, lang, cat, diff, text}`) — **ملكية عامة أو أصلية فقط**. يمكن إضافة `es` بنفس الشكل.

## إصدار تحديث

1. حدّث `RELEASE_NOTES_AR.md` (ملاحظات عربية تظهر في نافذة التحديث) وعدّل `update_config.json` عند الحاجة (`minSupportedVersion`, `mandatory`).
2. ادفع وسماً:
   ```bash
   git tag v1.2.0 && git push origin v1.2.0
   ```
3. يعمل `release.yml`: يشتق `versionName=1.2.0` و`versionCode=10200`، يشغّل `analyze` و`test`، يبني **APK + AAB** ويوقّعهما بالـKeystore (إن وُجدت الأسرار)، ينشئ GitHub Release، ثم يولّد `version.json` (versionCode، versionName، رابط APK، الحجم، SHA-256، ملاحظات عربية، minSupportedVersion، mandatory) ويدفعه وينشره على Pages. التطبيقات المثبتة خارج Play تكتشفه وتنزّل التحديث.
4. للتحديث **الإلزامي**: ضع `"mandatory": true` أو ارفع `minSupportedVersion` في `update_config.json` قبل وسم الإصدار. أما Google Play فارفع الـAAB إلى Play Console وسيتولى `in_app_update` الباقي.

## CI

- **Build** (كل push/PR): `flutter analyze` + `flutter test` + اختبارات Functions، ثم فحص Gradle مع إضافات Firebase (بإعداد وهمي) وبناء APK + AAB كـArtifacts.
- **Publish live content**: يبني الفهرس وينشر `content/` و`site/` و`version.json` على GitHub Pages.
- **Release** (وسم `v*`): كما أعلاه.

الأسرار التي يقرؤها الـWorkflow: `GOOGLE_SERVICES_JSON` (يُنشأ الملف وقت البناء)، `KEYSTORE_BASE64`، `KEY_ALIAS`، `KEY_PASSWORD`، `STORE_PASSWORD`، واختيارياً `ADMOB_APP_ID`، `ADMOB_REWARDED_ID`، `ADMOB_INTERSTITIAL_ID` (الافتراضي معرّفات اختبار). بدونها يُبنى APK يعمل كزائر/Offline ويُوقَّع بمفتاح debug (للاختبار وليس للنشر).

## ملاحظات أمان وخصوصية

- النتائج المرسلة للوحات تأتي من أوضاع «اللعب النقي» فقط (التحدي اليومي/الأسبوعي والاختبار الرسمي) وتمر عبر `submitScore` الذي يفحص WPM والفواصل الزمنية ويستبعد المشبوه.
- `verifyPurchase` يتحقق من المشتريات عبر Google Play Developer API عند إعداده (انظر `TODO_MANUAL.md`)؛ قبل ذلك تُسلَّم المشتريات مؤقتاً على الجهاز.
- لا يوجد Realtime Database؛ قواعد Firestore تقيّد كل مستخدم بمستنداته.
- الصوت والموسيقى مولّدة برمجياً (لا ملفات صوت). الخطوط: Tajawal وFira Mono وOpenDyslexic بترخيص SIL OFL (النصوص في `assets/fonts/OFL-*.txt` وتظهر في شاشة التراخيص).
