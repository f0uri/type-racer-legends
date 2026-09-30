# -*- coding: utf-8 -*-
import json, os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
from vocab_data import RAW
from gen_items import L, save, C
rnd = random.Random(7)

# ---------- vocab ----------
V = []
for lvl, raw in RAW.items():
    for i, pair in enumerate(raw.split(';')):
        en, ar = pair.split('|')
        if ' ' in en: continue
        V.append({"id": f"v{lvl}_{i:03d}", "en": en, "ar": ar, "level": lvl})
save("vocab", V)

# ---------- campaign ----------
BIOMES = [
 {"id":"city","name":L("المدينة","City","Ville"),"sky":["#ffb27a","#6d83c9"],"ground":"#2b2f3a","weather":"rain","mod":"storm","accent":"#ffd166","stages":9},
 {"id":"desert","name":L("الصحراء","Desert","Désert"),"sky":["#ffd18a","#ff8a5c"],"ground":"#b9874d","weather":"dust","mod":"storm","accent":"#ff9e00","stages":9},
 {"id":"forest","name":L("الغابة","Forest","Forêt"),"sky":["#b7e4c7","#2d6a4f"],"ground":"#3a3326","weather":"rain","mod":"fog","accent":"#95d5b2","stages":8},
 {"id":"snow","name":L("الثلج","Snow","Neige"),"sky":["#e0fbfc","#98c1d9"],"ground":"#c8d6e5","weather":"snow","mod":"ice","accent":"#7df9ff","stages":8},
 {"id":"neon","name":L("ليل النيون","Neon Night","Nuit Néon"),"sky":["#240046","#0b0221"],"ground":"#12101f","weather":"rain","mod":"blackout","accent":"#ff00e5","stages":8},
 {"id":"future","name":L("المدينة المستقبلية","Future City","Ville Futuriste"),"sky":["#0a1a3f","#00b4d8"],"ground":"#0d1b2a","weather":"storm","mod":"storm","accent":"#00f5d4","stages":8},
]
BOSSES = [
 {"id":"boss_city","name":L("توربو طارق","Turbo Tariq","Turbo Tarek"),"cc":"MA","persona":"aggressive","vehicle":"c_thunder","paint":"p_flames","wpmMul":1.06,
  "taunts":{"ar":["هل تظن أنك تستطيع اللحاق بي؟","الطريق ملكي!","أسرع يا صديقي، أسرع!","هذا كل ما عندك؟"],"en":["Think you can catch me?","This road is mine!","Faster, my friend, faster!","Is that all you've got?"]},
  "win":L("أحسنت! المدينة لك.","Well played! The city is yours.","Bien joué ! La ville est à toi."),"lose":L("هذا هو مكانك الطبيعي.","That's where you belong.","C'est ta place.")},
 {"id":"boss_desert","name":L("سلمى العاصفة","Sandstorm Salma","Salma la Tempête"),"cc":"EG","persona":"balanced","vehicle":"c_dune","paint":"p_camo","wpmMul":1.09,
  "taunts":{"ar":["الرمال لا ترحم المتعجلين.","أنا أسمع أنفاسك من هنا.","العاصفة قادمة!","ثبّت يديك وركّز."],"en":["The sand shows no mercy.","I can hear your breathing from here.","The storm is coming!","Steady hands, focus."]},
  "win":L("العاصفة انتهت... وأنت الفائز.","The storm is over... you win.","La tempête est finie... tu gagnes."),"lose":L("الصحراء علّمتك درساً.","The desert taught you a lesson.","Le désert t'a donné une leçon.")},
 {"id":"boss_forest","name":L("فيليكس الثعلب","Felix the Fox","Félix le Renard"),"cc":"FR","persona":"cautious","vehicle":"b_trail","paint":"p_chevron","wpmMul":1.11,
  "taunts":{"ar":["أنا لا أخطئ أبداً.","الهدوء يصنع الأبطال.","ستضيع بين الأشجار.","دقة، دقة، دقة."],"en":["I never make mistakes.","Calm makes champions.","You'll get lost among the trees.","Accuracy, accuracy, accuracy."]},
  "win":L("ثعلب ماكر خسر أمامك!","A clever fox lost to you!","Un renard rusé a perdu contre toi !"),"lose":L("الحذر يفوز دائماً.","Caution always wins.","La prudence gagne toujours.")},
 {"id":"boss_snow","name":L("فريا الجليد","Frostbite Freya","Freya Givre"),"cc":"NO","persona":"fatigue","vehicle":"c_frost","paint":"p_aurora","wpmMul":1.14,
  "taunts":{"ar":["البرد يبطئ الجميع... إلا أنا.","ستتجمد أصابعك.","الجليد ينتظر.","لا تنظر للخلف!"],"en":["Cold slows everyone... except me.","Your fingers will freeze.","The ice is waiting.","Don't look back!"]},
  "win":L("ذابت أمامك قلعة الجليد.","My ice castle melted before you.","Mon château de glace a fondu devant toi."),"lose":L("ابقَ بارداً وحاول مجدداً.","Stay cool and try again.","Reste calme et réessaie.")},
 {"id":"boss_neon","name":L("النينجا كينجي","Neon Ninja Kenji","Ninja Néon Kenji"),"cc":"JP","persona":"aggressive","vehicle":"b_grid","paint":"p_holo","wpmMul":1.17,
  "taunts":{"ar":["الظلام هو ساحتي.","لن ترى الكلمات التالية.","سريع كالظل.","اكتب من الذاكرة!"],"en":["Darkness is my arena.","You won't see the next words.","Fast as a shadow.","Type from memory!"]},
  "win":L("ظلّي يحييك.","My shadow salutes you.","Mon ombre te salue."),"lose":L("اختفيت في الظلام.","You vanished in the dark.","Tu as disparu dans l'obscurité.")},
 {"id":"boss_future","name":L("الملكة آريا","Quantum Queen Aria","Reine Quantique Aria"),"cc":"KR","persona":"balanced","vehicle":"c_phantom","paint":"p_galaxy","wpmMul":1.22,
  "taunts":{"ar":["حساباتي تقول إنك ستخسر.","المستقبل لي.","كل ضغطة أتوقعها.","استسلم للخوارزمية."],"en":["My calculations say you lose.","The future is mine.","I predict every keystroke.","Surrender to the algorithm."]},
  "win":L("حتى الخوارزميات تنحني لك.","Even algorithms bow to you.","Même les algorithmes s'inclinent."),"lose":L("النتيجة كما توقعت.","Result as predicted.","Résultat comme prévu.")},
]
STAGES = []
n = 0
cats_by_biome = {"city":["sentence","words_short"],"desert":["sentence","words_long"],"forest":["quote","sentence"],
                 "snow":["punctuation","numbers","sentence"],"neon":["code","symbols","sentence"],"future":["story","quote","symbols"]}
for bi, b in enumerate(BIOMES):
    for k in range(b["stages"]):
        n += 1
        boss = (k == b["stages"] - 1)
        t = (n - 1) / 49.0
        wpm = round(16 + 88 * (t ** 0.95))
        lmin = int(35 + 130 * t); lmax = int(lmin + 35 + 90 * t)
        mod = "none"
        if k >= b["stages"] // 2 or boss: mod = b["mod"]
        if b["id"] == "future" and k == b["stages"] - 2: mod = "blackout"
        opp = 2 + (1 if n > 6 else 0) + (1 if n > 18 else 0) + (1 if n > 34 else 0)
        STAGES.append({"n": n, "biome": b["id"], "boss": BOSSES[bi]["id"] if boss else None,
            "title": L(f"{b['name']['ar']} {k+1}" + (" — الزعيم" if boss else ""), f"{b['name']['en']} {k+1}" + (" — Boss" if boss else ""), f"{b['name']['fr']} {k+1}" + (" — Boss" if boss else "")),
            "lenMin": lmin, "lenMax": lmax, "cats": cats_by_biome[b["id"]], "mod": mod,
            "opp": {"count": min(6, opp + (1 if boss else 0)), "wpm": wpm}, "accStar": 90 + min(6, n // 9),
            "reward": {"coins": 60 + n * 14 + (300 if boss else 0), "xp": 40 + n * 6 + (120 if boss else 0), "gems": (25 if boss else 0)}})
json.dump({"version": 1, "biomes": BIOMES, "bosses": BOSSES, "items": STAGES}, open(os.path.join(C, 'campaign.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('campaign', len(STAGES))

# ---------- AI ----------
NAMES = "Alex:US;Amira:EG;Yuki:JP;Mateo:ES;Lina:MA;Omar:SA;Sofia:IT;Hans:DE;Chloe:FR;Liam:GB;Noor:AE;Ravi:IN;Mei:CN;Lucas:BR;Fatima:DZ;Youssef:TN;Elena:RU;Ahmed:JO;Zoe:CA;Jin:KR;Nadia:LB;Karim:MA;Emma:SE;Diego:AR;Hiro:JP;Layla:QA;Ivan:UA;Sara:MA;Tariq:PK;Anna:PL;Mohamed:EG;Leila:IR;Oscar:NL;Maya:IL;Pablo:MX;Hana:KR;Bilal:DZ;Clara:PT;Sami:SY;Nina:NO;Rayan:MA;Isla:AU;Kofi:GH;Amal:MA;Felix:AT;Dina:KW;Jonas:CH;Rim:TN;Tomas:CZ;Aya:JP;Zaid:IQ;Sienna:NZ;Malik:SN;Lola:CO;Adam:TR;Yara:BH;Nikolai:BG;Hugo:BE;Salma:MA;Ethan:IE;Mona:OM;Andre:ZA;Iris:GR;Reda:MA;Soraya:AF;Mila:HR;Kenji:JP;Dalia:LY;Theo:DK;Rania:PS;Viktor:HU;Selin:TR;Idris:NG;Camila:CL;Hamza:MA;Jade:FR;Nour:SD;Rafael:PT;Keira:GB;Anis:DZ;Lea:DE;Amine:MA;Ola:SE;Samir:ET;Tiana:PH;Boris:RS;Hadi:LB;Mariam:EG;Joao:BR;Ines:ES;Zakaria:MA;Elif:TR;Stefan:RO;Noa:FI;Yahya:YE;Lucia:PE;Marwan:JO;Kaito:JP;Sana:PK;Ali:IR;Wendy:SG;Aaron:US;Hind:MA".split(';')
PERS = {"aggressive":{"var":0.16,"err":0.055,"start":1.06,"fade":0.0},"balanced":{"var":0.10,"err":0.035,"start":1.0,"fade":0.0},
        "cautious":{"var":0.06,"err":0.015,"start":0.95,"fade":0.0},"fatigue":{"var":0.10,"err":0.03,"start":1.08,"fade":0.22}}
T = lambda ar, en: {"ar": ar, "en": en}
TAUNTS = {
 "aggressive":{"lead":[T("وداعاً!","See ya!"),T("أنت بطيء جداً!","Way too slow!"),T("لا تستطيع اللحاق بي!","Can't catch me!")],
               "behind":[T("سأتجاوزك قريباً!","I'm coming for you!"),T("لا تفرح!","Don't celebrate yet!")],
               "win":[T("سهل جداً!","Too easy!"),T("مرة أخرى؟","Again?")],"lose":[T("كانت لي فرصة ضائعة!","I'll get you next time!"),T("حظ سيئ...","Bad luck...")]},
 "balanced":{"lead":[T("سباق ممتع!","Nice race!"),T("أتقدم بثبات.","Steady ahead.")],
             "behind":[T("ما زال الوقت مبكراً.","Still early."),T("أحسنت، استمر!","Well done, keep going!")],
             "win":[T("مباراة جيدة!","Good game!"),T("سباق رائع.","Great race.")],"lose":[T("فزت عن جدارة!","You earned it!"),T("تهانيّ!","Congrats!")]},
 "cautious":{"lead":[T("دقة قبل سرعة.","Accuracy first."),T("بلا أخطاء.","No mistakes.")],
             "behind":[T("سأحافظ على هدوئي.","Staying calm."),T("الصبر مفتاح الفوز.","Patience wins.")],
             "win":[T("الحذر ينتصر.","Caution pays."),T("ثبات وهدوء.","Calm and steady.")],"lose":[T("سرعتك مذهلة.","You're quick!"),T("سأتدرب أكثر.","I'll practice more.")]},
 "fatigue":{"lead":[T("أنا في أوج قوتي!","I'm at full power!"),T("الانطلاقة ممتازة!","Great start!")],
            "behind":[T("أصابعي تتعب...","My fingers are tired..."),T("أحتاج استراحة!","Need a break!")],
            "win":[T("بالكاد وصلت!","Barely made it!"),T("آخ... يدايَ!","Phew... my hands!")],"lose":[T("فقدت طاقتي في النهاية.","Ran out of steam."),T("نفسي انقطع.","Out of breath.")]},
}
json.dump({"version": 1, "personalities": PERS, "taunts": TAUNTS, "names": [{"n": a.split(':')[0], "cc": a.split(':')[1]} for a in NAMES]},
          open(os.path.join(C, 'ai.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('ai names', len(NAMES))

# ---------- achievements ----------
def M(ar, en, fr): return (ar, en, fr)
ACH = [
 ("races",[10,50,250,1000],"races",[M("متسابق مبتدئ","Rookie Racer","Pilote Débutant"),M("متسابق منتظم","Regular Racer","Pilote Régulier"),M("محترف الطريق","Road Veteran","Vétéran de la Route"),M("أسطورة الطريق","Road Legend","Légende de la Route")],
   ("أكمل {n} سباقاً","Finish {n} races","Terminez {n} courses")),
 ("wins",[5,25,100,500],"trophy",[M("أول الانتصارات","First Wins","Premières Victoires"),M("فائز متمرس","Seasoned Winner","Gagnant Expérimenté"),M("بطل الحلبة","Track Champion","Champion de Piste"),M("سيد الانتصارات","Victory Master","Maître des Victoires")],
   ("افز في {n} سباقاً","Win {n} races","Gagnez {n} courses")),
 ("best_wpm",[30,50,75,100,130],"speed",[M("أصابع دافئة","Warm Fingers","Doigts Chauds"),M("كاتب سريع","Fast Typist","Dactylo Rapide"),M("برق الأصابع","Finger Lightning","Éclair des Doigts"),M("مئة كلمة!","Century Typist","Cent Mots !"),M("خارق السرعة","Supersonic","Supersonique")],
   ("اصل إلى {n} كلمة في الدقيقة","Reach {n} WPM","Atteignez {n} MPM")),
 ("best_acc",[95,98,100],"target",[M("دقيق","Precise","Précis"),M("شبه مثالي","Almost Perfect","Presque Parfait"),M("بلا أخطاء","Flawless","Sans Faute")],
   ("أنهِ سباقاً بدقة {n}%","Finish a race with {n}% accuracy","Terminez une course avec {n} % de précision")),
 ("combo_max",[25,50,100,200],"combo",[M("بداية الكومبو","Combo Starter","Débutant Combo"),M("سلسلة نارية","Fire Streak","Série de Feu"),M("ملك الكومبو","Combo King","Roi du Combo"),M("لا يُكسر","Unbreakable","Incassable")],
   ("حقق كومبو {n}","Reach a {n} combo","Atteignez un combo de {n}")),
 ("perfect_races",[1,10,50],"perfect",[M("سباق مثالي","Perfect Run","Course Parfaite"),M("مثالي متكرر","Perfectionist","Perfectionniste"),M("آلة الدقة","Precision Machine","Machine de Précision")],
   ("أنهِ {n} سباقات بدون أخطاء","Finish {n} races without errors","Terminez {n} courses sans erreur")),
 ("nitro_count",[10,100,500],"nitro",[M("شرارة نيترو","Nitro Spark","Étincelle Nitro"),M("مدمن النيترو","Nitro Addict","Accro au Nitro"),M("سيد النيترو","Nitro Master","Maître du Nitro")],
   ("فعّل النيترو {n} مرة","Trigger nitro {n} times","Activez le nitro {n} fois")),
 ("chars",[1000,10000,100000],"keys",[M("ألف حرف","Thousand Keys","Mille Touches"),M("عشرة آلاف حرف","Ten Thousand Keys","Dix Mille Touches"),M("ماراثون الأصابع","Keyboard Marathon","Marathon du Clavier")],
   ("اكتب {n} حرفاً صحيحاً","Type {n} correct characters","Tapez {n} caractères corrects")),
 ("streak_best",[3,7,30],"streak",[M("ثلاثة أيام","Three Days","Trois Jours"),M("أسبوع كامل","Full Week","Semaine Complète"),M("شهر من الالتزام","Month of Dedication","Mois de Dévouement")],
   ("حافظ على سلسلة {n} أيام","Keep a {n}-day streak","Gardez une série de {n} jours")),
 ("stages_cleared",[10,25,50],"map",[M("مستكشف الحملة","Campaign Explorer","Explorateur de Campagne"),M("نصف الطريق","Halfway There","À Mi-chemin"),M("قاهر الحملة","Campaign Conqueror","Conquérant de la Campagne")],
   ("أنهِ {n} مرحلة في الحملة","Clear {n} campaign stages","Terminez {n} étapes de campagne")),
 ("campaign_stars",[30,90,150],"star",[M("جامع النجوم","Star Collector","Collectionneur d'Étoiles"),M("سماء من النجوم","Sky of Stars","Ciel d'Étoiles"),M("كل النجوم","All the Stars","Toutes les Étoiles")],
   ("اجمع {n} نجمة","Collect {n} stars","Collectez {n} étoiles")),
 ("boss_defeated",[1,3,6],"boss",[M("صائد الزعماء","Boss Hunter","Chasseur de Boss"),M("قاهر الزعماء","Boss Crusher","Briseur de Boss"),M("ملك الزعماء","Boss Slayer","Tueur de Boss")],
   ("اهزم {n} زعيماً","Defeat {n} bosses","Battez {n} boss")),
 ("vehicles_owned",[3,8,15],"garage",[M("بداية الكراج","Small Garage","Petit Garage"),M("جامع المركبات","Vehicle Collector","Collectionneur"),M("متحف متنقل","Moving Museum","Musée Roulant")],
   ("امتلك {n} مركبة","Own {n} vehicles","Possédez {n} véhicules")),
 ("skins_owned",[5,20,50],"paint",[M("لمسة لون","A Touch of Color","Touche de Couleur"),M("مصمم","Stylist","Styliste"),M("خزانة الأناقة","Wardrobe Master","Maître de la Garde-robe")],
   ("امتلك {n} عنصر تخصيص","Own {n} customization items","Possédez {n} éléments de personnalisation")),
 ("level",[5,15,30,50],"level",[M("مستوى ٥","Level 5","Niveau 5"),M("مستوى ١٥","Level 15","Niveau 15"),M("مستوى ٣٠","Level 30","Niveau 30"),M("مستوى ٥٠","Level 50","Niveau 50")],
   ("اصل إلى المستوى {n}","Reach level {n}","Atteignez le niveau {n}")),
 ("rank_tier",[2,4],"rank",[M("فضي","Silver League","Ligue Argent"),M("بلاتيني","Platinum League","Ligue Platine")],
   ("اصل إلى الدوري رقم {n}","Reach league tier {n}","Atteignez le palier {n}")),
 ("tournaments_won",[1,5,20],"cup",[M("بطل البطولة","Tournament Champion","Champion du Tournoi"),M("بطل متكرر","Serial Champion","Champion en Série"),M("ملك البطولات","Tournament King","Roi des Tournois")],
   ("افز بـ {n} بطولات","Win {n} tournaments","Gagnez {n} tournois")),
 ("daily_done",[1,7,30],"calendar",[M("تحدي اليوم","Daily Challenger","Défi du Jour"),M("أسبوع من التحديات","Week of Challenges","Semaine de Défis"),M("شهر من التحديات","Month of Challenges","Mois de Défis")],
   ("أكمل {n} من التحديات اليومية","Complete {n} daily challenges","Terminez {n} défis quotidiens")),
 ("lessons_done",[1,10,30],"lesson",[M("أول درس","First Lesson","Première Leçon"),M("طالب مجتهد","Diligent Student","Élève Assidu"),M("خريج الكتابة باللمس","Touch Typing Graduate","Diplômé de la Dactylo")],
   ("أكمل {n} من دروس الكتابة","Complete {n} typing lessons","Terminez {n} leçons de frappe")),
 ("vocab_words",[25,100,300],"vocab",[M("مترجم صغير","Little Translator","Petit Traducteur"),M("قاموس متحرك","Walking Dictionary","Dictionnaire Vivant"),M("بطل المفردات","Vocabulary Hero","Héros du Vocabulaire")],
   ("اكتب ترجمة {n} كلمة صحيحة","Translate {n} words correctly","Traduisez {n} mots correctement")),
 ("powerups_used",[10,50,200],"power",[M("مجرّب القوى","Power Tester","Testeur de Pouvoirs"),M("خبير القوى","Power Expert","Expert en Pouvoirs"),M("سيد القوى","Power Lord","Seigneur des Pouvoirs")],
   ("استخدم {n} قوة بالكتابة","Use {n} typed power-ups","Utilisez {n} bonus tapés")),
 ("pit_perfect",[1,10,50],"pit",[M("صيانة سريعة","Quick Pit","Arrêt Rapide"),M("فريق الصيانة","Pit Crew","Équipe des Stands"),M("ميكانيكي مثالي","Master Mechanic","Mécanicien Parfait")],
   ("أتمم {n} صيانة (Pit Stop) بدقة 100%","Complete {n} perfect pit stops","Réussissez {n} arrêts aux stands parfaits")),
 ("combat_kills",[25,250],"combat",[M("مقاتل الطريق","Road Fighter","Combattant de la Route"),M("آلة الحرب","War Machine","Machine de Guerre")],
   ("دمّر {n} هدفاً في قتال الطريق","Destroy {n} targets in Road Combat","Détruisez {n} cibles au Combat Routier")),
 ("survival_best",[20,50,100],"survive",[M("ناجٍ","Survivor","Survivant"),M("صامد","Endurer","Endurant"),M("لا يُقهر","Invincible","Invincible")],
   ("اجتز {n} كلمة في سباق البقاء","Survive {n} words in Survival","Survivez à {n} mots")),
 ("world_stops",[3,6,12],"globe",[M("مسافر","Traveler","Voyageur"),M("جوّاب آفاق","Globetrotter","Globe-trotter"),M("حول العالم","Around the World","Tour du Monde")],
   ("أنهِ {n} محطات في رحلة العالم","Finish {n} World Tour stops","Terminez {n} étapes du Tour du Monde")),
 ("challenges_sent",[1,10],"link",[M("أول تحدٍّ","First Challenge","Premier Défi"),M("صانع التحديات","Challenge Maker","Créateur de Défis")],
   ("شارك {n} من روابط التحدي","Share {n} challenge links","Partagez {n} liens de défi")),
 ("certificates",[1],"cert",[M("حامل الشهادة","Certified Typist","Dactylo Certifié")],("احصل على شهادة WPM","Earn a WPM certificate","Obtenez un certificat MPM")),
 ("photo_finish_wins",[1,10],"camera",[M("فوز بالصورة","Photo Finish","Photo-finish"),M("صياد اللحظات","Split-second Hunter","Chasseur de Secondes")],
   ("افز بفارق ضئيل {n} مرة","Win a photo finish {n} time(s)","Gagnez {n} photo-finish")),
 ("upgrades",[5,20,50],"wrench",[M("ميكانيكي","Mechanic","Mécanicien"),M("مهندس","Engineer","Ingénieur"),M("عبقري المحركات","Engine Genius","Génie des Moteurs")],
   ("نفّذ {n} ترقية للمركبات","Perform {n} vehicle upgrades","Effectuez {n} améliorations")),
 ("quests_done",[10,50],"quest",[M("منفذ المهام","Quest Runner","Chasseur de Quêtes"),M("سيد المهام","Quest Master","Maître des Quêtes")],
   ("أكمل {n} مهمة","Complete {n} quests","Terminez {n} quêtes")),
]
AL = []; TITLES = {}
for metric, targets, icon, names, (dar, den, dfr) in ACH:
    for i, tgt in enumerate(targets):
        aid = f"a_{metric}_{i+1}"
        if metric == "rank_tier" and i == 1: pass
        reward = {"coins": 150 * (i + 1) ** 2 + 100}
        if i >= 1: reward["gems"] = 10 * i * i + 5
        d = {"id": aid, "metric": metric, "target": tgt, "icon": icon, "tier": i + 1, "of": len(targets),
             "name": L(*names[i]), "desc": L(dar.format(n=tgt), den.format(n=tgt), dfr.format(n=tgt)), "reward": reward, "enabled": True}
        if i == len(targets) - 1 and len(targets) >= 3:
            tid = "t_" + metric; d["title"] = tid; TITLES[tid] = L(*names[i])
        AL.append(d)
AL.append({"id":"a_rank_legend","metric":"rank_tier","target":6,"icon":"legend","tier":1,"of":1,"name":L("أسطورة الدوري","League Legend","Légende de la Ligue"),
  "desc":L("اصل إلى الدوري الأسطوري","Reach the Legendary league","Atteignez la ligue légendaire"),"reward":{"coins":5000,"gems":200},"title":"t_legend","enabled":True})
TITLES["t_legend"] = L("الأسطورة","The Legend","La Légende")
for k, v in [("t_tourn_daily", L("بطل اليوم","Daily Champion","Champion du Jour")), ("t_tourn_weekly", L("بطل الأسبوع","Weekly Champion","Champion de la Semaine")),
             ("t_rookie", L("مبتدئ","Rookie","Débutant"))]: TITLES[k] = v
json.dump({"version": 1, "titles": TITLES, "items": AL}, open(os.path.join(C, 'achievements.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('achievements', len(AL))

# ---------- quests ----------
Q = []
def q(id, period, metric, tgt, coins, ar, en, fr, gems=0, sp=20):
    Q.append({"id": id, "period": period, "metric": metric, "target": tgt, "reward": {"coins": coins, **({"gems": gems} if gems else {})}, "sp": sp,
              "name": L(ar.format(n=tgt), en.format(n=tgt), fr.format(n=tgt)), "enabled": True})
for t, c in [(3,150),(5,250),(8,400)]: q(f"d_races_{t}","daily","races",t,c,"أكمل {n} سباقات","Finish {n} races","Terminez {n} courses")
for t, c in [(1,200),(2,300),(3,450)]: q(f"d_wins_{t}","daily","wins",t,c,"افز في {n} سباقات","Win {n} races","Gagnez {n} courses")
for t, c in [(500,150),(1000,250),(2000,400)]: q(f"d_chars_{t}","daily","chars",t,c,"اكتب {n} حرفاً","Type {n} characters","Tapez {n} caractères")
q("d_perfect_1","daily","perfect_races",1,300,"أنهِ سباقاً بلا أخطاء","Finish an error-free race","Terminez une course sans erreur",gems=3)
q("d_nitro_3","daily","nitro_count",3,200,"فعّل النيترو {n} مرات","Trigger nitro {n} times","Activez le nitro {n} fois")
q("d_power_3","daily","powerups_used",3,200,"استخدم {n} قوى بالكتابة","Use {n} power-ups","Utilisez {n} bonus")
q("d_pit_1","daily","pit_perfect",1,250,"أنجز Pit Stop مثالي","Do a perfect pit stop","Réussissez un arrêt parfait")
q("d_lesson_1","daily","lessons_done",1,200,"أكمل درساً في الكتابة","Complete a typing lesson","Terminez une leçon")
q("d_vocab_10","daily","vocab_words",10,200,"ترجم {n} كلمات","Translate {n} words","Traduisez {n} mots")
q("d_combat_10","daily","combat_kills",10,250,"دمّر {n} أهداف","Destroy {n} targets","Détruisez {n} cibles")
for t, c, g in [(20,1200,10),(35,2000,20),(50,3000,30)]: q(f"w_races_{t}","weekly","races",t,c,"أكمل {n} سباقاً","Finish {n} races","Terminez {n} courses",gems=g,sp=80)
for t, c, g in [(10,1500,15),(20,2500,25)]: q(f"w_wins_{t}","weekly","wins",t,c,"افز في {n} سباقاً","Win {n} races","Gagnez {n} courses",gems=g,sp=80)
for t, c, g in [(6000,1500,15),(12000,2500,25)]: q(f"w_chars_{t}","weekly","chars",t,c,"اكتب {n} حرفاً","Type {n} characters","Tapez {n} caractères",gems=g,sp=80)
q("w_perfect_5","weekly","perfect_races",5,2000,"أنهِ {n} سباقات مثالية","Finish {n} perfect races","Terminez {n} courses parfaites",gems=20,sp=80)
q("w_daily_3","weekly","daily_done",3,1800,"أكمل {n} تحديات يومية","Complete {n} daily challenges","Terminez {n} défis quotidiens",gems=20,sp=80)
q("w_lessons_5","weekly","lessons_done",5,1500,"أكمل {n} دروس","Complete {n} lessons","Terminez {n} leçons",gems=15,sp=80)
q("w_tourn_2","weekly","tournaments_played",2,1800,"شارك في {n} بطولات","Play {n} tournaments","Jouez {n} tournois",gems=20,sp=80)
json.dump({"version": 1, "dailyCount": 3, "weeklyCount": 3, "items": Q}, open(os.path.join(C, 'quests.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('quests', len(Q))

# ---------- season / battle pass ----------
THEMES = [("الشرارة","Ignition","Ignition","#ff6b00"),("الجليد","Frostline","Ligne de Givre","#00b4d8"),("النيون","Neon Drift","Dérive Néon","#ff00e5"),
          ("الكثبان","Dune Storm","Tempête de Sable","#ffb703"),("الغابة","Wild Circuit","Circuit Sauvage","#38b000"),("الفضاء","Orbit","Orbite","#7209b7")]
TRACK = []
for lv in range(1, 41):
    free = {"coins": 200 + lv * 30}
    if lv % 5 == 0: free = {"gems": 10 + lv // 5 * 5}
    prem = {"gems": 15 + lv // 2}
    if lv % 2 == 1: prem = {"coins": 600 + lv * 60}
    if lv == 10: prem = {"skin": "r_neonring"}
    if lv == 20: prem = {"skin": "e_stars"}
    if lv == 30: prem = {"skin": "p_season1"}
    if lv == 40: prem = {"gems": 500, "skin": "s_crown"}
    if lv in (5, 15, 25, 35): prem = {"chest": "chest_gold"}
    TRACK.append({"level": lv, "free": free, "premium": prem})
json.dump({"version": 1, "anchor": "2026-09-29T00:00:00Z", "lengthDays": 28, "pointsPerLevel": 100, "maxLevel": 40,
           "themes": [{"name": L(a, b, c), "color": d} for a, b, c, d in THEMES], "track": TRACK, "premiumProduct": "battle_pass_premium"},
          open(os.path.join(C, 'season.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

# ---------- world tour ----------
CITIES = [("tangier","طنجة","Tangier","Tanger","MA","lighthouse",0),("paris","باريس","Paris","Paris","FR","eiffel",2000),("london","لندن","London","Londres","GB","bigben",340),
 ("rome","روما","Rome","Rome","IT","colosseum",1430),("cairo","القاهرة","Cairo","Le Caire","EG","pyramids",2130),("dubai","دبي","Dubai","Dubaï","AE","burj",2400),
 ("mumbai","مومباي","Mumbai","Bombay","IN","gateway",1930),("beijing","بكين","Beijing","Pékin","CN","pagoda",4700),("tokyo","طوكيو","Tokyo","Tokyo","JP","tokyotower",2100),
 ("sydney","سيدني","Sydney","Sydney","AU","opera",7800),("rio","ريو دي جانيرو","Rio de Janeiro","Rio de Janeiro","BR","christ",13300),("newyork","نيويورك","New York","New York","US","liberty",7700)]
WT = []
for i, (cid, ar, en, fr, cc, lm, km) in enumerate(CITIES):
    WT.append({"id": cid, "idx": i, "name": L(ar, en, fr), "cc": cc, "landmark": lm, "km": km, "minWpm": int(18 + i * 4.5), "opp": 2 + i // 4,
               "textIds": [f"w_{cid}{k:03d}" for k in range(3)], "reward": {"coins": 200 + i * 80, "xp": 80 + i * 15, "gems": 5 if i % 3 == 2 else 0},
               "colors": ["#"+("%06x" % rnd.randint(0x204060, 0xff9060)), "#"+("%06x" % rnd.randint(0x101030, 0x406080))]})
json.dump({"version": 1, "items": WT}, open(os.path.join(C, 'world.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

# ---------- tournaments ----------
TO = [
 {"id":"daily8","period":"daily","size":8,"rounds":3,"name":L("بطولة اليوم","Daily Cup","Coupe du Jour"),"cats":["sentence","quote"],
  "rewards":{"r1":{"coins":150},"r2":{"coins":300,"xp":60},"r3":{"coins":600,"xp":120,"gems":10},"win":{"coins":1200,"gems":30,"title":"t_tourn_daily","xp":250}}},
 {"id":"weekly16","period":"weekly","size":16,"rounds":4,"name":L("بطولة الأسبوع","Weekly Championship","Championnat de la Semaine"),"cats":["sentence","quote","story"],
  "rewards":{"r1":{"coins":250},"r2":{"coins":500},"r3":{"coins":900,"gems":10},"r4":{"coins":1500,"gems":25},"win":{"coins":3500,"gems":120,"title":"t_tourn_weekly","skin":"s_crown","xp":600}}},
]
json.dump({"version": 1, "items": TO}, open(os.path.join(C, 'tournaments.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

# ---------- shop + economy ----------
SHOP = {"version": 1,
 "gemPacks": [{"id":"gems_small","gems":120,"name":L("حزمة جواهر صغيرة","Small Gem Pack","Petit Pack de Gemmes")},
              {"id":"gems_medium","gems":650,"name":L("حزمة جواهر متوسطة","Medium Gem Pack","Pack de Gemmes Moyen")},
              {"id":"gems_large","gems":1500,"name":L("حزمة جواهر كبيرة","Large Gem Pack","Grand Pack de Gemmes")}],
 "products": {"removeAds":"remove_ads","battlePass":"battle_pass_premium"},
 "coinBundles": [{"id":"coins_a","gems":20,"coins":2000},{"id":"coins_b","gems":90,"coins":10000},{"id":"coins_c","gems":400,"coins":50000}],
 "chests": [
   {"id":"chest_bronze","name":L("صندوق برونزي","Bronze Chest","Coffre de Bronze"),"price":{"coins":800},"color":"#cd7f32",
    "drops":[{"w":70,"coins":[150,400]},{"w":25,"gems":[2,6]},{"w":5,"skinRarity":"common"}]},
   {"id":"chest_silver","name":L("صندوق فضي","Silver Chest","Coffre d'Argent"),"price":{"gems":40},"color":"#c0c0c0",
    "drops":[{"w":55,"coins":[500,1500]},{"w":30,"gems":[6,20]},{"w":15,"skinRarity":"rare"}]},
   {"id":"chest_gold","name":L("صندوق ذهبي","Gold Chest","Coffre d'Or"),"price":{"gems":120},"color":"#ffd700",
    "drops":[{"w":40,"coins":[1500,4000]},{"w":35,"gems":[20,60]},{"w":20,"skinRarity":"rare"},{"w":5,"skinRarity":"legendary"}]}],
}
json.dump(SHOP, open(os.path.join(C, 'shop.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print('done')

ECON = {"version": 1,
 "race": {"baseCoins": 18, "perWpm": 0.55, "rankMul": [1.0, 0.7, 0.5, 0.35, 0.25, 0.2, 0.15, 0.12], "minGuaranteed": 12, "dailyCoinCap": 2500,
          "xpBase": 25, "xpPerWpm": 0.45, "accBonusFrom": 95, "accBonus": 0.15, "riskMultiplier": 2.0, "rankedWin": 22, "rankedLoss": 12, "rankedMax": 40},
 "levels": {"xpBase": 120, "xpStep": 45, "maxLevel": 100},
 "upgrade": {"maxLevel": 5, "costBase": 400, "costGrowth": 1.85, "bonusPerLevel": 0.03, "gemCostAtMax": 0},
 "tiers": [{"id":"bronze","rp":0},{"id":"silver","rp":100},{"id":"gold","rp":300},{"id":"platinum","rp":600},{"id":"diamond","rp":1000},{"id":"master","rp":1500},{"id":"legend","rp":2200}],
 "ads": {"rewardedCoins": 150, "rewardedDailyLimit": 6, "interstitialEveryNRaces": 3, "interstitialEnabled": True, "interstitialMinSeconds": 180},
 "streak": {"rewards": [{"coins":100},{"coins":150},{"coins":200,"gems":2},{"coins":250},{"coins":300,"gems":3},{"coins":400},{"coins":600,"gems":10}]},
 "referral": {"level": 5, "inviterReward": {"coins": 3000, "gems": 30}, "inviteeReward": {"coins": 2000, "gems": 20}},
 "tests": {"officialSeconds": 60, "minAccuracy": 90},
 "breakMinutes": 45,
 "maxHumanWpm": 240,
}
json.dump(ECON, open(os.path.join(C, 'economy.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
