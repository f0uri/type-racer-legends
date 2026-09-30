# -*- coding: utf-8 -*-
import json, random, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from texts_data import *
OUT = os.path.join(os.path.dirname(__file__), '..', 'content', 'texts')
os.makedirs(OUT, exist_ok=True)
rnd = random.Random(20260930)

def diff(t):
    words = t.split()
    avg = sum(len(w) for w in words) / max(1, len(words))
    punct = sum(1 for c in t if not c.isalnum() and c != ' ')
    score = avg * 0.5 + punct / max(1, len(t)) * 12 + len(t) / 120
    return max(1, min(5, int(score / 1.1)))

def item(pref, i, t, cat, topic, lang, src=None):
    d = {"id": f"{pref}{i:03d}", "t": t, "cat": cat, "topic": topic, "lang": lang, "diff": diff(t), "len": len(t)}
    if src: d["src"] = src
    return d

def dump(name, items):
    with open(os.path.join(OUT, name + '.json'), 'w', encoding='utf-8') as f:
        json.dump({"version": 1, "items": items}, f, ensure_ascii=False, indent=0)
    print(name, len(items))
    return len(items)

total = 0
# words
items = []
for i in range(60):
    k = rnd.randint(10, 14); items.append(item('ews', i, ' '.join(rnd.sample(WORDS_SHORT, k)), 'words_short', 'general', 'en'))
for i in range(40):
    k = rnd.randint(6, 8); items.append(item('ewl', i, ' '.join(rnd.sample(WORDS_LONG, k)), 'words_long', 'general', 'en'))
total += dump('en_words', items)
# sentences
items = []
for topic, arr in SENT.items():
    for i, s in enumerate(arr):
        items.append(item('es_' + topic[:3], i, s, 'sentence', topic, 'en'))
# pairs of short sentences as medium texts
for topic, arr in SENT.items():
    for i in range(6):
        a, b = rnd.sample(arr, 2)
        items.append(item('em_' + topic[:3], i, a + ' ' + b, 'sentence', topic, 'en'))
total += dump('en_sentences', items)
total += dump('en_quotes', [item('eq', i, q, 'quote', 'quotes', 'en', a) for i, (q, a) in enumerate(QUOTES)])
total += dump('en_stories', [item('est', i, s, 'story', 'stories', 'en') for i, s in enumerate(STORIES)])
# punctuation & numbers
R=rnd.randint
P_T=[
 lambda: "Wait, what? No way! It costs $%d.%02d, right?"%(R(2,99),R(0,99)),
 lambda: "Dear friend, on %d/%d/2026 we'll meet at %d:%02d p.m.; don't be late!"%(R(1,12),R(1,28),R(1,11),R(0,59)),
 lambda: "Order #%d: %d items, total $%d.%02d (tax included)."%(R(100,999),R(2,9),R(10,400),R(0,99)),
 lambda: "\"Ready?\" she asked. \"Yes,\" he said, \"let's go; we have %d minutes.\""%R(2,45),
 lambda: "Room %d, floor %d: call 555-%04d before %d:%02d a.m., please."%(R(101,499),R(1,9),R(0,9999),R(6,11),R(0,59)),
 lambda: "Score: %d-%d! That's +%d%% better than last week, isn't it?"%(R(2,9),R(0,4),R(5,80)),
 lambda: "Tickets (%d adults, %d children) cost $%d; bring your ID, okay?"%(R(1,4),R(0,3),R(20,160)),
 lambda: "In %d days, we'll travel %d km; that's %d.%d hours by train!"%(R(2,30),R(120,980),R(1,9),R(0,9)),
 lambda: "Is it %d + %d = %d? Yes; and %d - %d = %d, too."%((a:=R(2,60)),(b:=R(2,60)),a+b,(c:=R(40,99)),(d:=R(2,39)),c-d),
 lambda: "Coordinates: %d.%d N, %d.%d E; altitude %d m; temperature %d C."%(R(10,60),R(0,99),R(1,120),R(0,99),R(5,3000),R(-5,38)),
]
items = []
for i in range(40):
    items.append(item('epn', i, P_T[i % len(P_T)](), 'numbers' if i % 2 else 'punctuation', 'punct_numbers', 'en'))
total += dump('en_punct', items)
S_T=[
 lambda: "user_%d@mail.com | pass: P@ss#%d! | ref=%d&id=%d"%(R(2,999),R(100,999),R(1,99),R(100,999)),
 lambda: "if (a[%d] >= b[%d] && c != %d) { x += %d * 2; }"%(R(0,9),R(0,9),R(1,50),R(1,20)),
 lambda: "https://game.example/race?id=%d&lvl=%d#top"%(R(100,999),R(1,50)),
 lambda: "C:\\Games\\Racer\\save_%d.dat -> 100%% (%d/%d)"%(R(1,9),R(10,99),R(100,200)),
 lambda: '{ "speed": %d, "nitro": [%d, %d], "ok": true }'%(R(80,300),R(0,9),R(0,9)),
 lambda: "#%06x ~ rgb(%d, %d, %d) * 50%% + $%d"%(R(0x100000,0xFFFFFF),R(0,255),R(0,255),R(0,255),R(1,99)),
 lambda: "$total = ($a + $b) * %d / %d; // ~%d%%"%(R(2,9),R(2,9),R(10,99)),
 lambda: "<tag id=\"n%d\" value='%d'> & </tag> @%d"%(R(1,99),R(1,99),R(1,99)),
]
items = [item('esy', i, S_T[i % len(S_T)](), 'symbols', 'symbols', 'en') for i in range(32)]
total += dump('en_symbols', items)
total += dump('en_code', [item('ecd', i, s, 'code', 'code', 'en') for i, s in enumerate(CODE)])
# french
items = [item('fs', i, s, 'sentence', 'general', 'fr') for i, s in enumerate(FR_SENT)]
items += [item('fq', i, q, 'quote', 'quotes', 'fr', a) for i, (q, a) in enumerate(FR_QUOTES)]
FRW = "rapide vitesse course voiture moto route virage victoire champion piste casque moteur liberté soleil montagne étoile chemin courage amitié musique village jardin marché voyage pluie vent neige forêt désert océan lumière sourire patience équipe énergie".split()
for i in range(22):
    items.append(item('fw', i, ' '.join(rnd.sample(FRW, rnd.randint(8, 11))), 'words_short', 'general', 'fr'))
total += dump('fr_all', items)
items = [item('ss', i, s, 'sentence', 'general', 'es') for i, s in enumerate(ES_SENT)]
total += dump('es_all', items)
# world tour
items = []
for city, arr in WORLD.items():
    for i, s in enumerate(arr):
        items.append(item('w_' + city, i, s, 'world', city, 'en'))
total += dump('en_world', items)
total += dump('en_official', [item('eo', i, s, 'official', 'official', 'en') for i, s in enumerate(OFFICIAL)])
print('TOTAL', total)
