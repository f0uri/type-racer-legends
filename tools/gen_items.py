# -*- coding: utf-8 -*-
import json, os
C = os.path.join(os.path.dirname(__file__), '..', 'content')
def L(ar, en, fr): return {"ar": ar, "en": en, "fr": fr}
def save(name, items, extra=None):
    d = {"version": 1}
    if extra: d.update(extra)
    d["items"] = items
    json.dump(d, open(os.path.join(C, name + '.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(name, len(items))

# ---------------- vehicles ----------------
CAR = {
 "hatch":   dict(wb=[.22,.76], wr=.085, ride=.05, belt=.20, roof=.36, rx0=.26, rx1=.62, ax=.12, fx=.72, hood=.21, nose=.12, tail=.22, wing=0),
 "sedan":   dict(wb=[.20,.78], wr=.085, ride=.05, belt=.20, roof=.34, rx0=.30, rx1=.62, ax=.17, fx=.74, hood=.21, nose=.12, tail=.23, wing=0),
 "coupe":   dict(wb=[.20,.78], wr=.085, ride=.045, belt=.19, roof=.31, rx0=.33, rx1=.60, ax=.20, fx=.76, hood=.19, nose=.10, tail=.21, wing=0),
 "muscle":  dict(wb=[.19,.79], wr=.092, ride=.05, belt=.22, roof=.33, rx0=.30, rx1=.58, ax=.18, fx=.72, hood=.23, nose=.13, tail=.24, wing=1),
 "rally":   dict(wb=[.21,.77], wr=.095, ride=.07, belt=.22, roof=.35, rx0=.27, rx1=.60, ax=.13, fx=.72, hood=.22, nose=.13, tail=.24, wing=2),
 "suv":     dict(wb=[.21,.78], wr=.098, ride=.08, belt=.24, roof=.40, rx0=.22, rx1=.66, ax=.08, fx=.76, hood=.25, nose=.15, tail=.30, wing=0),
 "pickup":  dict(wb=[.20,.80], wr=.100, ride=.08, belt=.23, roof=.40, rx0=.52, rx1=.72, ax=.45, fx=.80, hood=.24, nose=.15, tail=.23, wing=0, bed=1),
 "supercar":dict(wb=[.19,.79], wr=.088, ride=.035, belt=.16, roof=.27, rx0=.36, rx1=.58, ax=.22, fx=.72, hood=.15, nose=.08, tail=.17, wing=2),
 "formula": dict(wb=[.20,.80], wr=.100, ride=.04, belt=.12, roof=.21, rx0=.44, rx1=.52, ax=.36, fx=.60, hood=.10, nose=.06, tail=.14, wing=3, open=1),
 "hyper":   dict(wb=[.18,.80], wr=.090, ride=.03, belt=.15, roof=.25, rx0=.38, rx1=.56, ax=.24, fx=.70, hood=.13, nose=.07, tail=.15, wing=2),
}
BIKE = {
 "scooter": dict(wb=[.12,.86], wr=.12, seat=[.30,.42], tank=[.40,.66,.42], fair=.5, bars=[.78,.62], fork=.10, exh=.0, stepthru=1, cc=.3),
 "naked":   dict(wb=[.10,.88], wr=.15, seat=[.30,.50], tank=[.38,.62,.54], fair=0, bars=[.72,.70], fork=.14, exh=.22, cc=.5),
 "cafe":    dict(wb=[.10,.88], wr=.15, seat=[.26,.50], tank=[.36,.62,.55], fair=.15, bars=[.68,.62], fork=.15, exh=.28, cc=.6),
 "dirt":    dict(wb=[.10,.88], wr=.17, seat=[.30,.56], tank=[.40,.62,.58], fair=.1, bars=[.72,.76], fork=.22, exh=.25, cc=.6, high=1),
 "cruiser": dict(wb=[.08,.92], wr=.15, seat=[.26,.44], tank=[.40,.66,.52], fair=0, bars=[.70,.72], fork=.26, exh=.32, cc=.9),
 "sport":   dict(wb=[.10,.88], wr=.15, seat=[.26,.52], tank=[.40,.66,.56], fair=.75, bars=[.66,.62], fork=.15, exh=.26, cc=.8),
 "chopper": dict(wb=[.06,.96], wr=.15, seat=[.22,.42], tank=[.36,.56,.52], fair=0, bars=[.80,.76], fork=.40, exh=.34, cc=1.0, long=1),
 "super":   dict(wb=[.10,.88], wr=.15, seat=[.24,.52], tank=[.38,.66,.58], fair=1, bars=[.64,.60], fork=.16, exh=.26, cc=1.0),
 "neon":    dict(wb=[.10,.90], wr=.16, seat=[.28,.50], tank=[.38,.66,.54], fair=.6, bars=[.66,.60], fork=.14, exh=.0, cc=.9, tron=1),
 "hyper":   dict(wb=[.08,.92], wr=.15, seat=[.24,.50], tank=[.36,.70,.58], fair=1, bars=[.64,.58], fork=.16, exh=.30, cc=1.2, wing=1),
}
V = []
def veh(id, kind, style, rarity, price, cur, lvl, names, stats, cols, unlock=None, **kw):
    d = {"id": id, "type": "vehicle", "kind": kind, "style": style, "name": L(*names), "rarity": rarity,
         "price": {cur: price} if price else {}, "unlock": unlock or ({"level": lvl} if lvl > 1 else {}),
         "enabled": True, "startsAt": None, "endsAt": None,
         "stats": dict(zip(["accel", "stab", "nitro", "earn"], stats)),
         "colors": dict(zip(["primary", "secondary", "accent"], cols)),
         "shape": (CAR if kind == "car" else BIKE)[style], "tags": []}
    d.update(kw); V.append(d)
# cars
veh("c_sprout","car","hatch","common",0,"coins",1,("سبراوت الشارع","Street Sprout","Petit Sprint"),(3,4,3,3),("#ff5a3c","#2b2d42","#ffd166"))
veh("c_urban","car","sedan","common",1500,"coins",2,("أوربان كروزر","Urban Cruiser","Croiseur Urbain"),(4,5,3,4),("#3a86ff","#1b263b","#e0fbfc"))
veh("c_sunset","car","coupe","common",3500,"coins",3,("كوبيه الغروب","Sunset Coupe","Coupé Soleil"),(5,4,4,4),("#ff8a00","#3d2c8d","#ffe066"))
veh("c_hauler","car","pickup","common",5000,"coins",5,("هولر الصحراء","Desert Hauler","Pick-up du Désert"),(4,7,3,6),("#c9a227","#4a3b22","#fff3b0"))
veh("c_dune","car","rally","rare",9000,"coins",6,("رالي الكثبان","Dune Rally","Rallye des Dunes"),(6,7,5,5),("#2a9d8f","#264653","#e9c46a"))
veh("c_frost","car","suv","rare",12000,"coins",8,("فروست رانر","Frost Runner","Coureur Givré"),(5,8,5,6),("#8ecae6","#023047","#ffb703"))
veh("c_thunder","car","muscle","rare",14000,"coins",9,("ثاندر ماسل","Thunder Muscle","Muscle Tonnerre"),(8,5,6,5),("#d00000","#1d1d1d","#f8f9fa"))
veh("c_vortex","car","supercar","rare",28000,"coins",14,("فورتكس GT","Vortex GT","Vortex GT"),(8,7,7,6),("#7209b7","#10002b","#f72585"))
veh("c_apex","car","formula","legendary",600,"gems",20,("أبيكس فورميلا","Apex Formula","Apex Formule"),(10,7,8,8),("#e63946","#f1faee","#ffd60a"))
veh("c_phantom","car","hyper","legendary",900,"gems",25,("فانتوم نيون","Neon Phantom","Fantôme Néon"),(10,9,9,9),("#00f5d4","#0b0f2a","#ff00e5"))
# bikes
veh("b_pocket","bike","scooter","common",0,"coins",1,("بوكيت روكيت","Pocket Rocket","Mini Fusée"),(3,4,3,3),("#ffbe0b","#3a0ca3","#ffffff"))
veh("b_fang","bike","naked","common",2000,"coins",2,("ستريت فانغ","Street Fang","Croc de Rue"),(5,4,3,4),("#06d6a0","#073b4c","#ffd166"))
veh("b_cafe","bike","cafe","common",4000,"coins",4,("كافيه ريترو","Retro Cafe","Café Racer"),(5,5,4,5),("#b08968","#1b1b1b","#ede0d4"))
veh("b_trail","bike","dirt","rare",8500,"coins",6,("تريل بليزر","Trail Blazer","Tout-Terrain"),(6,7,5,5),("#ff7b00","#1d3557","#f1faee"))
veh("b_king","bike","cruiser","rare",13000,"coins",9,("ملك الطريق","Highway King","Roi de la Route"),(5,9,6,6),("#6d6875","#0d1b2a","#e5989b"))
veh("b_crimson","bike","sport","rare",16000,"coins",11,("كريمزون سبورت","Crimson Sport","Sport Cramoisi"),(8,6,7,5),("#c1121f","#14213d","#fca311"))
veh("b_iron","bike","chopper","rare",20000,"coins",13,("أيرون تشوبر","Iron Chopper","Chopper de Fer"),(6,8,6,8),("#495057","#212529","#ffba08"))
veh("b_silver","bike","super","legendary",500,"gems",18,("الرصاصة الفضية","Silver Bullet","Balle d'Argent"),(9,8,8,7),("#ced4da","#212529","#00b4d8"))
veh("b_grid","bike","neon","legendary",800,"gems",22,("جريد رانر","Grid Runner","Coureur du Réseau"),(9,7,10,8),("#0b132b","#1c2541","#00f5ff"))
veh("b_solar","bike","hyper","legendary",1000,"gems",28,("شبح الشمس","Solar Wraith","Spectre Solaire"),(10,9,9,9),("#ff9e00","#240046","#ffea00"))
# event / achievement exclusives
veh("c_crescent","car","sedan","legendary",0,"coins",1,("نجمة الهلال","Crescent Star","Étoile du Croissant"),(8,8,8,10),("#0b6e4f","#ffd60a","#f8f9fa"),{"event":"ramadan_2027"},tags=["event","ramadan"])
veh("b_lantern","bike","cafe","legendary",0,"coins",1,("فارس الفانوس","Lantern Rider","Cavalier Lanterne"),(8,8,8,10),("#7b2cbf","#ffd60a","#fff3b0"),{"event":"ramadan_2027"},tags=["event","ramadan"])
veh("c_striker","car","supercar","legendary",0,"coins",1,("المهاجم الذهبي","Golden Striker","Buteur Doré"),(9,8,8,9),("#ffd700","#0a0a0a","#ffffff"),{"event":"worldcup_2026"},tags=["event","football"])
veh("b_notebook","bike","scooter","rare",0,"coins",1,("سكوتر الدفتر","Notebook Scooter","Scooter Cahier"),(6,6,6,8),("#4cc9f0","#3a0ca3","#ffee32"),{"event":"back_to_school_2026"},tags=["event","school"])
veh("c_legend","car","hyper","legendary",0,"coins",1,("إصدار الأساطير","Legends Edition","Édition Légendes"),(10,10,10,10),("#ffd700","#111111","#ff2e63"),{"achievement":"a_rank_legend"},tags=["achievement"])
save("vehicles", V)

# ---------------- skins ----------------
S = []
def skin(id, slot, rarity, price, cur, names, params, lvl=1, unlock=None, kinds=None, tags=None):
    S.append({"id": id, "type": "skin", "slot": slot, "name": L(*names), "rarity": rarity,
              "price": {cur: price} if price else {}, "unlock": unlock or ({"level": lvl} if lvl > 1 else {}),
              "enabled": True, "startsAt": None, "endsAt": None, "params": params,
              "kinds": kinds or ["car", "bike"], "tags": tags or []})
def paint(id, rarity, price, cur, names, pattern, cols, lvl=1, unlock=None, tags=None, **kw):
    p = {"pattern": pattern, "colors": cols}; p.update(kw)
    skin(id, "paint", rarity, price, cur, names, p, lvl, unlock, tags=tags)
paint("p_red","common",0,"coins",("أحمر السباق","Racing Red","Rouge Course"),"solid",["#e5383b"])
paint("p_blue","common",300,"coins",("أزرق المحيط","Ocean Blue","Bleu Océan"),"solid",["#1d6ff2"])
paint("p_lime","common",300,"coins",("أخضر ليموني","Lime Green","Vert Citron"),"solid",["#8ac926"])
paint("p_yellow","common",300,"coins",("أصفر الشمس","Sun Yellow","Jaune Soleil"),"solid",["#ffca3a"])
paint("p_white","common",400,"coins",("أبيض لؤلؤي","Pearl White","Blanc Perle"),"solid",["#f1f3f5"],metallic=True)
paint("p_black","common",400,"coins",("أسود منتصف الليل","Midnight Black","Noir Minuit"),"solid",["#15161a"],metallic=True)
paint("p_orange","common",500,"coins",("برتقالي لهّاب","Orange Blaze","Orange Flamme"),"solid",["#ff6b00"])
paint("p_violet","common",500,"coins",("بنفسجي حالم","Violet Dream","Violet Rêve"),"solid",["#9d4edd"],metallic=True)
paint("p_stripes","rare",1800,"coins",("خطان متوازيان","Twin Stripes","Double Bande"),"stripes",["#1d3557","#f1faee","#e63946"],lvl=3)
paint("p_checker","rare",2200,"coins",("علم السباق","Checker Flag","Damier"),"checker",["#f8f9fa","#111111"],lvl=4)
paint("p_carbon","rare",2600,"coins",("ألياف الكربون","Carbon Fiber","Fibre de Carbone"),"carbon",["#23262b","#3b4048"],lvl=6)
paint("p_camo","rare",2400,"coins",("تمويه الصحراء","Desert Camo","Camouflage Désert"),"camo",["#c2a878","#8c7a4f","#5e5034"],lvl=5)
paint("p_fade","rare",3000,"coins",("تدرج الغروب","Sunset Fade","Dégradé Coucher"),"gradient",["#ff9e00","#ff2e63","#3a0ca3"],lvl=7)
paint("p_flames","rare",3600,"coins",("لهب حارق","Hot Flames","Flammes Ardentes"),"flames",["#1b1b1b","#ff6b00","#ffd60a"],lvl=8)
paint("p_chevron","rare",3200,"coins",("شيفرون","Chevron","Chevron"),"chevron",["#0b132b","#3a86ff","#ffffff"],lvl=9)
paint("p_dots","rare",2800,"coins",("نقاط البوب","Pop Dots","Pois Pop"),"dots",["#ff006e","#ffbe0b","#ffffff"],lvl=6)
paint("p_aurora","legendary",250,"gems",("شفق قطبي","Aurora","Aurore"),"gradient",["#00f5d4","#7209b7","#3a86ff"],lvl=12,shimmer=True)
paint("p_galaxy","legendary",350,"gems",("مجرة","Galaxy","Galaxie"),"galaxy",["#10002b","#5a189a","#e0aaff"],lvl=15,shimmer=True)
paint("p_gold","legendary",400,"gems",("كروم ذهبي","Gold Chrome","Chrome Doré"),"solid",["#ffd700"],lvl=18,metallic=True,shimmer=True)
paint("p_holo","legendary",450,"gems",("هولو بريزم","Holo Prism","Prisme Holo"),"rainbow",["#ff0054","#ffbd00","#00f5d4","#3a86ff"],lvl=20,shimmer=True)
paint("p_crescent","legendary",0,"coins",("هلال رمضان","Ramadan Crescent","Croissant Ramadan"),"crescent",["#0b6e4f","#ffd60a","#ffffff"],unlock={"event":"ramadan_2027"},tags=["event","ramadan"])
paint("p_worldcup","legendary",0,"coins",("ذهب البطولة","Champion Gold","Or du Champion"),"checker",["#ffd700","#0a0a0a"],unlock={"event":"worldcup_2026"},tags=["event","football"])
paint("p_school","rare",0,"coins",("دفتر المدرسة","Notebook","Cahier"),"stripes",["#f8f9fa","#4361ee","#ef476f"],unlock={"event":"back_to_school_2026"},tags=["event","school"])
paint("p_legend","legendary",0,"coins",("ذهب الأساطير","Legend Gold","Or Légende"),"galaxy",["#3d2c00","#ffd700","#fff3b0"],unlock={"achievement":"a_rank_legend"},tags=["achievement"],shimmer=True)
paint("p_season1","legendary",0,"coins",("سكن الموسم الأول","Season 1 Blaze","Flamme Saison 1"),"flames",["#10002b","#00f5d4","#ffffff"],unlock={"season":{"id":1,"level":30,"premium":True}},tags=["season"],shimmer=True)
# rims
def rim(id, rarity, price, cur, names, style, color, glow=None, lvl=1, **kw):
    p = {"style": style, "color": color}; 
    if glow: p["glow"] = glow
    p.update(kw); skin(id, "rims", rarity, price, cur, names, p, lvl)
rim("r_classic","common",0,"coins",("كلاسيك ٥","Classic 5","Classique 5"),"spoke5","#dfe3e8")
rim("r_mesh","common",600,"coins",("ميش برو","Mesh Pro","Mesh Pro"),"mesh","#c0c6cf",lvl=2)
rim("r_disc","common",700,"coins",("قرص فولاذي","Disc Steel","Disque Acier"),"disc","#9aa4b2",lvl=3)
rim("r_star","rare",1600,"coins",("نجمة متوهجة","Star Burst","Étoile"),"star","#ffd166",lvl=5)
rim("r_split","rare",1800,"coins",("سبليت ٦","Split Six","Split Six"),"split","#e0e1dd",lvl=7)
rim("r_turbine","rare",2200,"coins",("توربين","Turbine","Turbine"),"turbine","#b9e6ff",lvl=9)
rim("r_neonring","legendary",180,"gems",("حلقة نيون","Neon Ring","Anneau Néon"),"mesh","#0b132b","#00f5ff",lvl=12)
rim("r_fire","legendary",220,"gems",("جنوط نارية","Fire Rims","Jantes de Feu"),"turbine","#2b0a00","#ff6b00",lvl=16)
# neon
def neon(id, rarity, price, cur, names, color, lvl=1, **kw):
    p = {"color": color}; p.update(kw); skin(id, "neon", rarity, price, cur, names, p, lvl)
neon("n_cyan","common",800,"coins",("نيون سماوي","Cyan Glow","Néon Cyan"),"#00f5ff",lvl=3)
neon("n_pink","common",800,"coins",("نيون وردي","Magenta Glow","Néon Rose"),"#ff2bd6",lvl=3)
neon("n_green","common",900,"coins",("نيون أخضر","Toxic Green","Vert Toxique"),"#39ff14",lvl=4)
neon("n_orange","rare",1500,"coins",("نيون برتقالي","Amber Glow","Néon Ambre"),"#ff9100",lvl=6)
neon("n_white","rare",1500,"coins",("نيون أبيض","Ice White","Blanc Glacé"),"#f5faff",lvl=8,pulse=True)
neon("n_rainbow","legendary",200,"gems",("نيون قوس قزح","Rainbow Pulse","Pulsation Arc-en-ciel"),"#ff00ff",lvl=14,pulse=True,rainbow=True)
# exhaust
def exh(id, rarity, price, cur, names, effect, color, lvl=1):
    skin(id, "exhaust", rarity, price, cur, names, {"effect": effect, "color": color}, lvl)
exh("e_smoke","common",0,"coins",("دخان عادي","Plain Smoke","Fumée Simple"),"smoke","#c9ced6")
exh("e_sparks","common",900,"coins",("شرر","Sparks","Étincelles"),"sparks","#ffd166",lvl=3)
exh("e_fire","rare",1800,"coins",("نار العادم","Backfire","Backfire"),"fire","#ff6b00",lvl=6)
exh("e_electric","rare",2000,"coins",("كهرباء","Electric","Électrique"),"electric","#7df9ff",lvl=8)
exh("e_bubbles","rare",1600,"coins",("فقاعات","Bubbles","Bulles"),"bubbles","#9bf6ff",lvl=5)
exh("e_stars","legendary",160,"gems",("نجوم","Stardust","Poussière d'étoiles"),"stars","#fff3b0",lvl=11)
exh("e_rainbow","legendary",240,"gems",("قوس قزح","Rainbow Trail","Traînée Arc-en-ciel"),"rainbow","#ff00ff",lvl=15)
# nitro flames
def flame(id, rarity, price, cur, names, cols, shape="cone", lvl=1):
    skin(id, "nitroFlame", rarity, price, cur, names, {"colors": cols, "shape": shape}, lvl)
flame("f_blue","common",0,"coins",("لهب أزرق","Blue Flame","Flamme Bleue"),["#7df9ff","#2a6bff","#ffffff"])
flame("f_purple","common",1200,"coins",("لهب بنفسجي","Purple Flame","Flamme Violette"),["#e0aaff","#7b2cbf","#ffffff"],lvl=4)
flame("f_green","rare",1800,"coins",("لهب سام","Toxic Flame","Flamme Toxique"),["#b9fbc0","#38b000","#ffffff"],"dual",lvl=7)
flame("f_gold","rare",2400,"coins",("لهب ذهبي","Golden Flame","Flamme Dorée"),["#fff3b0","#ffb703","#ff6b00"],"wave",lvl=9)
flame("f_pink","rare",2200,"coins",("لهب وردي","Pink Flame","Flamme Rose"),["#ffc8dd","#ff006e","#ffffff"],"spark",lvl=8)
flame("f_white","legendary",200,"gems",("لهب أبيض","White-hot","Blanc Brûlant"),["#ffffff","#b9e6ff","#7df9ff"],"dual",lvl=13)
flame("f_ice","legendary",260,"gems",("لهب جليدي","Ice Flame","Flamme de Glace"),["#e0fbfc","#3a86ff","#00f5ff"],"wave",lvl=17)
# stickers
def stk(id, rarity, price, cur, names, shape, color, lvl=1, **kw):
    p = {"shape": shape, "color": color}; p.update(kw); skin(id, "sticker", rarity, price, cur, names, p, lvl)
stk("s_star","common",300,"coins",("نجمة","Star","Étoile"),"star","#ffd166")
stk("s_bolt","common",300,"coins",("صاعقة","Bolt","Éclair"),"bolt","#ffea00",lvl=2)
stk("s_flame","common",400,"coins",("لهب","Flame","Flamme"),"flame","#ff6b00",lvl=3)
stk("s_heart","common",400,"coins",("قلب","Heart","Cœur"),"heart","#ff4d6d",lvl=3)
stk("s_seven","rare",900,"coins",("رقم ٧","Number 7","Numéro 7"),"number","#ffffff",lvl=5,number=7)
stk("s_arrow","rare",900,"coins",("سهم","Arrow","Flèche"),"arrow","#00f5ff",lvl=5)
stk("s_wing","rare",1400,"coins",("جناحان","Wings","Ailes"),"wing","#e0e1dd",lvl=8)
stk("s_skull","rare",1500,"coins",("جمجمة","Skull","Crâne"),"skull","#f8f9fa",lvl=10)
stk("s_crown","legendary",120,"gems",("تاج","Crown","Couronne"),"crown","#ffd700",lvl=14)
stk("s_crescent","legendary",0,"coins",("هلال","Crescent","Croissant"),"crescent","#ffd60a",unlock={"event":"ramadan_2027"},tags=["event","ramadan"])
stk("s_ball","rare",0,"coins",("كرة","Ball","Ballon"),"ball","#ffffff",unlock={"event":"worldcup_2026"},tags=["event","football"])
# plates
def plate(id, rarity, price, cur, names, bg, fg, border, lvl=1, **kw):
    p = {"bg": bg, "fg": fg, "border": border}; p.update(kw); skin(id, "plate", rarity, price, cur, names, p, lvl)
plate("pl_classic","common",0,"coins",("لوحة كلاسيكية","Classic Plate","Plaque Classique"),"#f8f9fa","#111111","#111111")
plate("pl_gold","rare",1000,"coins",("لوحة ذهبية","Black Gold","Noir & Or"),"#111111","#ffd700","#ffd700",lvl=5)
plate("pl_neon","rare",1400,"coins",("لوحة نيون","Neon Plate","Plaque Néon"),"#0b132b","#00f5ff","#00f5ff",lvl=8,glow=True)
plate("pl_flag","legendary",100,"gems",("لوحة الأبطال","Champion Plate","Plaque Champion"),"#ffd700","#111111","#ffffff",lvl=12)
# horns (synth definition: sequence of [freqHz, ms], wave)
def horn(id, rarity, price, cur, names, wave, seq, lvl=1):
    skin(id, "horn", rarity, price, cur, names, {"wave": wave, "seq": seq}, lvl)
horn("h_classic","common",0,"coins",("بوق عادي","Classic Beep","Klaxon Classique"),"square",[[440,220]])
horn("h_deep","common",700,"coins",("بوق عميق","Deep Horn","Klaxon Grave"),"saw",[[196,450]],lvl=2)
horn("h_double","common",900,"coins",("بوق مزدوج","Double Beep","Double Klaxon"),"square",[[523,120],[0,60],[523,120]],lvl=3)
horn("h_sport","rare",1500,"coins",("بوق رياضي","Sport Horn","Klaxon Sport"),"saw",[[330,100],[440,100],[587,200]],lvl=6)
horn("h_retro","rare",1600,"coins",("بوق قديم","Ooga Retro","Klaxon Rétro"),"sine",[[220,260],[165,360]],lvl=7)
horn("h_fanfare","legendary",150,"gems",("فانفير النصر","Victory Fanfare","Fanfare"),"square",[[392,120],[392,120],[392,120],[523,400]],lvl=12)
# celebrations
def cel(id, rarity, price, cur, names, typ, cols, lvl=1, **kw):
    p = {"type": typ, "colors": cols}; p.update(kw); skin(id, "celebration", rarity, price, cur, names, p, lvl, **({} if 'unlock' not in kw else {}))
cel("ce_confetti","common",0,"coins",("قصاصات ملونة","Confetti","Confettis"),"confetti",["#ff006e","#ffbe0b","#3a86ff","#8338ec"])
cel("ce_fireworks","common",1200,"coins",("ألعاب نارية","Fireworks","Feux d'artifice"),"fireworks",["#ffd166","#ef476f","#06d6a0"],lvl=4)
cel("ce_donut","rare",2000,"coins",("دوران الدونات","Donut Spin","Donut"),"donut",["#e0e1dd","#ff6b00"],lvl=7)
cel("ce_wheelie","rare",2200,"coins",("وقوف على عجلة","Wheelie","Cabrage"),"wheelie",["#ffd60a","#ffffff"],lvl=9)
cel("ce_lightning","legendary",180,"gems",("صواعق","Lightning","Éclairs"),"lightning",["#7df9ff","#ffffff"],lvl=13)
cel("ce_flags","rare",1800,"coins",("أعلام السباق","Racing Flags","Drapeaux"),"flags",["#ffffff","#111111"],lvl=6)
cel("ce_smoke","rare",1900,"coins",("حلقات الدخان","Smoke Rings","Anneaux de Fumée"),"smoke",["#dee2e6","#adb5bd"],lvl=8)
save("skins", S)

# ---------------- outfits ----------------
O = []
def outfit(id, rarity, price, cur, names, helmet, suit, suit2, visor, lvl=1, unlock=None, tags=None, style="full"):
    O.append({"id": id, "type": "outfit", "name": L(*names), "rarity": rarity, "price": {cur: price} if price else {},
              "unlock": unlock or ({"level": lvl} if lvl > 1 else {}), "enabled": True, "startsAt": None, "endsAt": None,
              "params": {"helmet": helmet, "suit": suit, "suit2": suit2, "visor": visor, "style": style}, "tags": tags or []})
outfit("o_default","common",0,"coins",("زي المتسابق","Rookie Suit","Combinaison Débutant"),"#e5383b","#2b2d42","#e5383b","#111827")
outfit("o_blue","common",800,"coins",("الفارس الأزرق","Blue Rider","Pilote Bleu"),"#1d6ff2","#0b132b","#3a86ff","#0a0a0a",lvl=2)
outfit("o_night","rare",1800,"coins",("فارس الليل","Night Rider","Pilote de Nuit"),"#15161a","#0b0b0f","#00f5ff","#00f5ff",lvl=5,style="stripe")
outfit("o_desert","rare",2000,"coins",("بدوي الصحراء","Desert Nomad","Nomade du Désert"),"#c9a227","#8c7a4f","#5e5034","#2b2118",lvl=7)
outfit("o_arctic","rare",2200,"coins",("مستكشف القطب","Arctic Explorer","Explorateur Arctique"),"#e0fbfc","#3a86ff","#f1faee","#1b263b",lvl=9)
outfit("o_cyber","legendary",220,"gems",("سايبر","Cyber Suit","Combinaison Cyber"),"#10002b","#1a1a2e","#ff00e5","#ff00e5",lvl=14,style="stripe")
outfit("o_gold","legendary",300,"gems",("بطل ذهبي","Gold Champion","Champion Doré"),"#ffd700","#7a5c00","#ffd700","#111111",lvl=18)
outfit("o_ramadan","legendary",0,"coins",("زي رمضان","Ramadan Suit","Tenue Ramadan"),"#0b6e4f","#0b3d2e","#ffd60a","#111111",unlock={"event":"ramadan_2027"},tags=["event","ramadan"])
outfit("o_school","rare",0,"coins",("زي المدرسة","School Suit","Tenue Scolaire"),"#4361ee","#3a0ca3","#ffee32","#111111",unlock={"event":"back_to_school_2026"},tags=["event","school"])
outfit("o_legend","legendary",0,"coins",("زي الأسطورة","Legend Suit","Combinaison Légende"),"#ffd700","#111111","#ff2e63","#ffd700",unlock={"achievement":"a_rank_legend"},tags=["achievement"],style="stripe")
save("outfits", O)

# ---------------- events ----------------
E = []
def ev(id, names, desc, start, end, color, featured, bonus=1.0, icon="event", pool=None):
    E.append({"id": id, "type": "event", "name": L(*names), "desc": L(*desc), "enabled": True, "startsAt": start, "endsAt": end,
              "color": color, "icon": icon, "xpMultiplier": bonus, "featured": featured,
              "tasks": [
                {"id": id + "_t1", "metric": "races", "target": 10, "reward": {"coins": 500}},
                {"id": id + "_t2", "metric": "wins", "target": 5, "reward": {"gems": 30}},
                {"id": id + "_t3", "metric": "chars", "target": 3000, "reward": {"coins": 1500}},
                {"id": id + "_t4", "metric": "perfect_races", "target": 3, "reward": {"gems": 60}},
                {"id": id + "_t5", "metric": "combo_max", "target": 40, "reward": {"coins": 1000}}],
              "finalReward": {"gems": 150}})
ev("back_to_school_2026",("العودة للمدارس","Back to School","Rentrée"),
   ("اجمع المهام واحصل على سكنات المدرسة الحصرية!","Complete the tasks to unlock exclusive school skins!","Terminez les tâches pour débloquer des skins exclusifs !"),
   "2026-09-01T00:00:00Z","2026-10-31T23:59:59Z","#4361ee",["b_notebook","p_school","o_school"],1.25,"school")
ev("ramadan_2027",("رمضان","Ramadan","Ramadan"),
   ("مركبات وسكنات رمضانية حصرية طوال الشهر الفضيل.","Exclusive Ramadan vehicles and skins all month long.","Véhicules et skins exclusifs de Ramadan tout le mois."),
   "2027-02-08T00:00:00Z","2027-03-11T23:59:59Z","#0b6e4f",["c_crescent","b_lantern","p_crescent","o_ramadan","s_crescent"],1.5,"moon")
ev("winter_neon_2026",("نيون الشتاء","Winter Neon","Néon d'Hiver"),
   ("سباقات ليلية مضيئة ومكافآت شتوية.","Glowing night races and winter rewards.","Courses nocturnes lumineuses et récompenses d'hiver."),
   "2026-12-15T00:00:00Z","2027-01-15T23:59:59Z","#00b4d8",["n_white","f_ice"],1.25,"snow")
ev("worldcup_2026",("كأس العالم","World Cup","Coupe du Monde"),
   ("انتهى الحدث. السكنات الحصرية لمن جمعها فقط.","Event ended. Exclusive skins remain for those who collected them.","Événement terminé. Les skins exclusifs restent à ceux qui les ont obtenus."),
   "2026-06-01T00:00:00Z","2026-07-25T23:59:59Z","#2a9d8f",["c_striker","p_worldcup","s_ball"],1.5,"football")
save("events", E)
