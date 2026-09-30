#!/usr/bin/env python3
"""Generates content/lessons.json: a 30-lesson touch-typing course (QWERTY). Deterministic; original material.
Real words come from the shipped English texts; pseudo-words fill the early lessons that only use a few letters."""
import json, glob, os, re, random
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
words = set()
for f in glob.glob(os.path.join(ROOT, 'content/texts/en_*.json')):
    for t in json.load(open(f, encoding='utf-8'))['items']:
        for w in re.findall(r"[a-z]+", t['t'].lower()):
            if 2 <= len(w) <= 9: words.add(w)
words = sorted(words)
VOW = set('aeiou')

# (ar title, en title, new keys, extra allowed chars, kind)
PLAN = [
 ('مفتاحا السبابة: F و J', 'Index fingers: F and J', 'fj', '', 'keys'),
 ('الوسطى: D و K', 'Middle fingers: D and K', 'dk', '', 'keys'),
 ('البنصر: S و L', 'Ring fingers: S and L', 'sl', '', 'keys'),
 ('الخنصر: A و ;', 'Pinkies: A and ;', 'a;', '', 'keys'),
 ('السبابة الممتدة: G و H', 'Reaching index: G and H', 'gh', '', 'keys'),
 ('مراجعة الصف الرئيسي', 'Home row review', '', '', 'review'),
 ('الصف العلوي: E و I', 'Top row: E and I', 'ei', '', 'keys'),
 ('الصف العلوي: R و U', 'Top row: R and U', 'ru', '', 'keys'),
 ('الصف العلوي: T و Y', 'Top row: T and Y', 'ty', '', 'keys'),
 ('الصف العلوي: W و O', 'Top row: W and O', 'wo', '', 'keys'),
 ('الصف العلوي: Q و P', 'Top row: Q and P', 'qp', '', 'keys'),
 ('مراجعة الصف العلوي', 'Top row review', '', '', 'review'),
 ('الصف السفلي: V و M', 'Bottom row: V and M', 'vm', '', 'keys'),
 ('الصف السفلي: C و الفاصلة', 'Bottom row: C and comma', 'c,', '', 'keys'),
 ('الصف السفلي: X و النقطة', 'Bottom row: X and period', 'x.', '', 'keys'),
 ('الصف السفلي: Z و /', 'Bottom row: Z and slash', 'z/', '', 'keys'),
 ('الصف السفلي: B و N', 'Bottom row: B and N', 'bn', '', 'keys'),
 ('مراجعة الصف السفلي', 'Bottom row review', '', '', 'review'),
 ('الحروف الكبيرة (Shift)', 'Capital letters (Shift)', '', '', 'caps'),
 ('الأرقام 1 إلى 5', 'Numbers 1 to 5', '12345', '', 'numbers'),
 ('الأرقام 6 إلى 0', 'Numbers 6 to 0', '67890', '', 'numbers'),
 ('علامات الترقيم', 'Punctuation', '?!', '', 'punct'),
 ('علامات الاقتباس والشرطة', 'Quotes and dashes', '\'"-', '', 'punct2'),
 ('الكلمات الشائعة', 'Common words', '', '', 'common'),
 ('جمل قصيرة', 'Short sentences', '', '', 'sentences'),
 ('بناء السرعة', 'Speed building', '', '', 'sentences'),
 ('الرموز @ # $ % & *', 'Symbols @ # $ % & *', '@#$%&*', '', 'symbols'),
 ('الأقواس', 'Brackets', '()[]{}', '', 'brackets'),
 ('كود برمجي بسيط', 'Simple code', '=+<>_', '', 'code'),
 ('الاختبار النهائي', 'Final exam', '', '', 'final'),
]
FINGERS_AR = {
 'fj': 'ضع السبابتين على F و J (بروزان صغيران).', 'dk': 'الوسطى على D و K.', 'sl': 'البنصر على S و L.', 'a;': 'الخنصر على A و ;.',
 'gh': 'السبابة تتحرك للجانب: G باليسرى و H باليمنى.', 'ei': 'E بالوسطى اليسرى، I بالوسطى اليمنى.', 'ru': 'R بالسبابة اليسرى، U بالسبابة اليمنى.',
 'ty': 'T باليسرى و Y باليمنى (امتداد للداخل).', 'wo': 'W بالبنصر الأيسر، O بالبنصر الأيمن.', 'qp': 'Q و P بالخنصرين.', 'vm': 'V بالسبابة اليسرى، M باليمنى.',
 'c,': 'C بالوسطى اليسرى، الفاصلة بالوسطى اليمنى.', 'x.': 'X بالبنصر الأيسر، النقطة بالبنصر الأيمن.', 'z/': 'Z و / بالخنصرين.', 'bn': 'B باليسرى و N باليمنى.',
}

def rng(n): return random.Random(1000 + n)

def pseudo(r, letters, focus, n):
    letters = [c for c in letters if c.isalpha()]
    vow = [c for c in letters if c in VOW]; con = [c for c in letters if c not in VOW]
    out = []
    for _ in range(n):
        ln = r.choice([2, 3, 3, 4, 4, 5])
        w = ''
        for i in range(ln):
            pool = (vow if (i % 2 == 1 and vow) else con) or letters
            if focus and r.random() < 0.55: pool = [c for c in focus if c.isalpha() and c in pool] or pool
            w += r.choice(pool)
        out.append(w)
    return out

def real(r, allowed, focus, n):
    a = set(allowed)
    pool = [w for w in words if set(w) <= a and (not focus or any(c in w for c in focus))]
    if len(pool) < 6: return []
    r.shuffle(pool)
    return pool[:n]

def pad(text, lo=70, hi=130):
    return text if len(text) <= hi else text[:hi].rsplit(' ', 1)[0]

items = []
learned = ''
for i, (ar, en, new, extra, kind) in enumerate(PLAN, 1):
    r = rng(i)
    learned += new
    letters = ''.join(sorted(set(c for c in learned if c.isalpha())))
    if kind in ('keys', 'review') and not letters: letters = 'fj'
    focus = ''.join(c for c in new if c.isalpha()) or letters
    allowed_letters = letters or 'fjdksla;'
    drills = []
    if kind in ('keys', 'review'):
        combos = []
        fs = (new if new else letters)
        for _ in range(10):
            combos.append(''.join(r.choice(fs or letters) for _ in range(r.choice([2, 3, 3, 4]))))
        a = ' '.join(combos)
        b = ' '.join(pseudo(r, allowed_letters, focus, 12))
        rw = real(r, allowed_letters, focus, 10)
        c = ' '.join(rw) if rw else ' '.join(pseudo(r, allowed_letters, focus, 10))
        drills = [a, b, c]
    elif kind == 'caps':
        ws = real(r, 'abcdefghijklmnopqrstuvwxyz', '', 14)
        drills = [' '.join(w.capitalize() for w in ws[:6]), ' '.join((w.capitalize() if k % 2 == 0 else w) for k, w in enumerate(ws[6:12])), 'The Quick Brown Fox Jumps Over The Lazy Dog Near Paris And Rome']
    elif kind == 'numbers':
        ds = new
        nums = lambda n: ' '.join(''.join(r.choice(ds) for _ in range(r.choice([2, 3, 4]))) for _ in range(n))
        drills = [nums(10), 'room ' + nums(3) + ' floor ' + nums(3), 'call ' + nums(4) + ' now']
    elif kind == 'punct':
        drills = ['Yes, no, maybe. Go, stop, wait. Why? Now! Well, fine.', 'Hello, world! Are you ready? Yes, I am. Let us go!', 'First, plan. Then, act. Finally, learn! Why not? Try again.']
    elif kind == 'punct2':
        drills = ["it's I'm don't can't we're they'll she's", 'He said "go" and she said "wait" - then we left.', "A well-known fact: it's hard-earned; don't stop - keep going."]
    elif kind == 'common':
        common = 'the be to of and a in that have it for not on with he as you do at this but his by from they we say her she or an will my one all would there their what so up out if about who get which go me when make can like time no just him know take people into year your good some could them see other than then now look only come its over think also back after use two how our work first well way even new want because any these give day most us'.split()
        r.shuffle(common)
        drills = [' '.join(common[:14]), ' '.join(common[14:28]), ' '.join(common[28:42])]
    elif kind == 'sentences':
        sents = []
        for f in sorted(glob.glob(os.path.join(ROOT, 'content/texts/en_sentences.json'))):
            sents += [t['t'] for t in json.load(open(f, encoding='utf-8'))['items'] if t['len'] <= 75 and t.get('diff', 2) <= (2 if i == 25 else 3)]
        r.shuffle(sents)
        drills = [sents[0], sents[1], sents[2]]
    elif kind == 'symbols':
        drills = ['user@mail.com #tag 50% $20 R&D *note*', 'Save 25% on $40 - email me@site.org & #win *now*', 'C&A 100% #1 $9.99 team@club.io *star* & more']
    elif kind == 'brackets':
        drills = ['(one) [two] {three} (four) [five] {six}', 'list[0] = (a + b) * {c}; call(x, [y], {z});', '(first (second [third {fourth}]))']
    elif kind == 'code':
        drills = ['x = a + b; y = x * 2; z = y - 1;', 'if (n > 0) { total = total + n; } else { total = 0; }', 'for (i = 0; i < 10; i++) { sum += i; } a_b = c_d;']
    elif kind == 'final':
        sents = []
        for t in json.load(open(os.path.join(ROOT, 'content/texts/en_sentences.json'), encoding='utf-8'))['items']:
            if 60 <= t['len'] <= 110 and t.get('diff', 3) >= 2: sents.append(t['t'])
        r.shuffle(sents)
        drills = [sents[0], sents[1], sents[2]]
    text = ' '.join(d.strip() for d in drills)
    if kind not in ('sentences', 'final'): text = pad(text, hi=150)
    text = re.sub(r'\s+', ' ', text).strip()
    hint_key = ''.join(sorted(new)) if new else ''
    hint = next((v for k, v in FINGERS_AR.items() if sorted(k) == sorted(new)), 'ابقِ أصابعك على الصف الرئيسي وانظر إلى الشاشة لا إلى لوحة المفاتيح.')
    target = round(12 + i * 0.85 + (6 if kind == 'final' else 0))
    items.append({
        'id': f'l{i:02d}', 'n': i, 'kind': kind, 'title': {'ar': ar, 'en': en}, 'focus': new, 'allowed': ''.join(sorted(set(learned + ' '))),
        'hint': hint, 'text': text, 'len': len(text), 'targetWpm': target, 'minAcc': 92 if i < 25 else 94,
        'reward': {'coins': 60 + i * 12, 'xp': 25 + i * 4, **({'gems': 15} if kind == 'final' else {})},
    })
out = {'version': 1, 'items': items}
json.dump(out, open(os.path.join(ROOT, 'content/lessons.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(items), 'lessons; avg len', sum(x['len'] for x in items) // len(items), 'min', min(x['len'] for x in items), 'max', max(x['len'] for x in items))
