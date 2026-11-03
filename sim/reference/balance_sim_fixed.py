# FIXED COPY of balance_sim.py: black cards drawn by diamonds while blocking were never added to the
# hand, so they vanished for the rest of the floor. This copy adds them to the hand (one line, marked "FIX").
# Original: 34.8 % wins. Fixed: 65.0 % wins (20 000 runs).
"""
balance_sim.py – Monte Carlo-simulering av mini-deckbuildern (solo).

Kör:
    python3 balance_sim.py                    # gällande regler, 20 000 omgångar
    python3 balance_sim.py --runs 50000
    python3 balance_sim.py --compare          # alla varianter vi testade
    python3 balance_sim.py --hand 4 --cap 6   # egna värden (se run() för alla parametrar)

Utdata: vinst %, förluster per våning (% av alla omgångar), vinst % per temakung, antal låsta omgångar.

Bot-beteende (medvetet enkelt):
- spelar ALLA kort av rätt färg mot fiendekortet
- sparar det högsta ospelade kortet
- belöning: väljer den färg leken har minst summa av, högst valör
- byter ut lägsta kortet av samma färg när leken är full; ♣ tar bort lägsta kortet
- offrar ett ess (värde 14) bara vid block och bara när missen annars kostar 2 liv
- röd joker fästs på högsta kortet efter knektvåningen

Inte modellerat: mods (modesset), essoffer i attack, ess i egen färg.
Kortformat: [valör, färg, modifierare]  färg H/D/S/C, 'J' = svart joker.
"""
import random, argparse
RED = {'H', 'D'}; BLACK = {'S', 'C'}

# card = [rank, suit, mod]   mod: None | 'dual' | 'innate' | 'double' | 'draw2'
def is_red(c): return c[1] in RED or c[2] == 'dual'
def is_black(c): return c[1] in BLACK or c[2] == 'dual'
def val(c): return c[0] * (2 if c[2] == 'double' else 1)

BOON = {'H': 'dual', 'D': 'innate', 'S': 'double', 'C': 'draw2'}

def run(seed, hand=4, retain=1, lives=3, mode='choice', cap=6, heart_heal=True,
        joker_on=True, enemy_bonus=0, boss_bonus=0, graded=None, short=(), ace_sac=False,
        boss_twice=False, boss_hand=None):
    """En omgång. mode: 'choice' = lägg till tills leken har cap kort, sedan byt;
    'add' = lägg alltid till; 'swap' = byt alltid. Returnerar (våning, 'win'|'dead'|'loop', stats)."""
    rng = random.Random(seed)
    deck = [[2, 'H', None], [2, 'D', None], [2, 'S', None], [2, 'C', None]]
    max_lives = lives
    theme = rng.choice('HDSC')  # dragen kung före start
    stats = {'theme': theme}
    for floor in range(3, 14):
        # bygg fiende
        if floor == 13:
            enemy = [[13 + boss_bonus, s, None] for s in 'HDSC' if s != theme]
            if boss_twice:
                enemy += [[13 + boss_bonus, s, None] for s in 'HDSC' if s != theme]
            if joker_on:
                enemy.append([0, 'J', theme])
        else:
            enemy = [[floor + enemy_bonus, s, None] for s in 'HDSC']
        rng.shuffle(enemy)
        if floor in short: enemy = enemy[:3]
        draw = deck[:]; rng.shuffle(draw); disc = []; kept = []; shield = 0
        # innate kort först
        draw.sort(key=lambda c: c[2] == 'innate')  # innate hamnar sist = dras först
        beaten = []; rounds = 0

        def drawone():
            nonlocal draw, disc
            if not draw:
                if not disc: return None
                draw = disc; disc = []; rng.shuffle(draw)
            return draw.pop()

        while enemy:
            rounds += 1
            if rounds > 80: return floor, 'loop', stats
            cur = [enemy.pop(0)]
            # svart joker
            if cur[0][1] == 'J':
                t = cur[0][2]
                beaten.append(cur[0])
                if t == 'H':  # kungen läker: ett slaget kort tillbaka
                    kings = [c for c in beaten if c[1] != 'J']
                    if kings:
                        k = kings[-1]; beaten.remove(k); enemy.append(k)
                    continue
                elif t == 'D':
                    cur = [[14, 'D', None]]
                elif t == 'S':
                    cur = [[14, 'S', None]]
                elif t == 'C':  # dubbel runda
                    cur = [enemy.pop(0)] if enemy else []
                    if enemy: cur.append(enemy.pop(0))
                    if not cur: continue
            h = kept[:]; kept = []
            lim = boss_hand if (floor == 13 and boss_hand) else hand
            while len(h) < lim:
                c = drawone()
                if c is None: break
                h.append(c)
            # draw2 effekt
            extra = []
            for c in h:
                if c[2] == 'draw2':
                    for _ in range(2):
                        x = drawone()
                        if x: extra.append(x)
            h += extra
            need_block = sum(e[0] for e in cur if e[1] in BLACK)
            need_atk = sum(e[0] for e in cur if e[1] in RED)
            # fördela dual-kort till det som behövs mest
            reds = [c for c in h if c[1] in RED]
            blacks = [c for c in h if c[1] in BLACK]
            duals = [c for c in h if c[2] == 'dual']
            reds = [c for c in reds if c[2] != 'dual']; blacks = [c for c in blacks if c[2] != 'dual']
            for d in duals:
                if need_block > sum(val(c) for c in reds) + shield: reds.append(d)
                elif need_atk > 0: blacks.append(d)
                else: reds.append(d)
            # ruter drar kort vid block
            if need_block:
                for c in list(reds):
                    if c[1] == 'D':
                        x = drawone()
                        if x:
                            h.append(x)  # FIX
                            if is_red(x): reds.append(x)
                            else: blacks.append(x)
            played = []
            if need_block:
                blk = sum(val(c) for c in reds) + shield; shield = 0
                played += reds
                miss = need_block - blk
                dmg = 0 if miss <= 0 else (2 if graded and miss >= graded else 1)
                if dmg == 2 and ace_sac and lives >= 2:
                    lives -= 1; stats['sac'] = stats.get('sac', 0) + 1; blk += 14; miss = need_block - blk; dmg = 0 if miss <= 0 else 1
                if blk >= need_block:
                    over = blk - need_block
                    hv = sum(val(c) for c in reds if c[1] == 'H')
                    shield = min(over, hv)
                else:
                    lives -= dmg
                    if lives <= 0: return floor, 'dead', stats
                beaten += [e for e in cur if e[1] in BLACK]
            if need_atk:
                atk = 0; clubs = 0
                for c in blacks:
                    atk += val(c) * 3 // 2 if c[1] == 'S' else val(c)
                    clubs += c[1] == 'C'
                if clubs >= 2: atk += 2
                played += blacks
                reds_e = [e for e in cur if e[1] in RED]
                if atk >= need_atk:
                    beaten += reds_e
                else:
                    if not any(x[1] in BLACK for x in enemy):
                        lives -= 1
                        if lives <= 0: return floor, 'dead', stats
                        beaten += reds_e
                    else:
                        enemy += reds_e
            rest = [c for c in h if c not in played]
            rest.sort(key=val, reverse=True)
            kept = rest[:retain]; disc += played + rest[retain:]
        # ---- belöning ----
        if floor == 13: break
        last = beaten[-1]
        pool = [c for c in beaten if c[1] != 'J' and c[0] > 0]
        pool = [[c[0], c[1], None] for c in pool]
        rng.shuffle(pool)
        rsuit = last[1] if last[1] in 'HDSC' else 'S'

        def best(opts):
            redv = sum(val(c) for c in deck if is_red(c)); blkv = sum(val(c) for c in deck if is_black(c))
            want = RED if redv <= blkv else BLACK
            o = [c for c in opts if c[1] in want] or opts
            return max(o, key=lambda c: c[0])

        def gain(c):
            if mode == 'add' or (mode == 'choice' and len(deck) < cap):
                deck.append(c)
            else:
                same = [d for d in deck if is_red(d) == (c[1] in RED) and d[2] is None] or [d for d in deck if d[2] is None] or deck
                w = min(same, key=val)
                if val(w) < c[0]:
                    deck.remove(w); deck.append(c)

        def trim():
            if len(deck) > 4:
                w = min([d for d in deck if d[2] is None] or deck, key=val)
                deck.remove(w)

        if rsuit == 'S':
            gain(best(pool))
        elif rsuit == 'C':
            gain(best(pool[:2])); trim()
        elif rsuit == 'H':
            if heart_heal and lives < max_lives: lives += 1
            else: gain(best(pool[:2]))
        elif rsuit == 'D':
            for c in pool[:2]: gain(c)
        # röd joker efter knekt
        if floor == 11 and joker_on:
            tgt = max([d for d in deck if d[2] is None], key=val)
            tgt[2] = BOON[theme]
    return 14, 'win', stats

def stats(N=20000, **kw):
    res = [run(i, **kw) for i in range(N)]
    w = sum(o == 'win' for f, o, s in res) / N
    loops = sum(o == 'loop' for f, o, s in res)
    dist = {}
    for f, o, s in res:
        if o != 'win': dist[f] = dist.get(f, 0) + 1
    by = {}
    for t in 'HDSC':
        sub = [o for f, o, s in res if s['theme'] == t]
        by[t] = round(100 * sum(o == 'win' for o in sub) / len(sub), 1)
    return round(w * 100, 1), {k: round(v / N * 100, 1) for k, v in sorted(dist.items())}, by, loops

# Gällande regler (= regelverket i projektet)
CURRENT = dict(hand=4, retain=1, lives=3, mode='choice', cap=5, graded=5,
               short=(3, 4, 5), ace_sac=True, boss_hand=3)

# Varianterna från designsessionen 2026-11-03
VARIANTS = [
    ('Original: n=3, behåll 1, max 6 kort', dict(hand=3, cap=6)),
    ('n=4, max 6 kort, färgbelöningar', dict(cap=6)),
    ('n=4, max 5 kort', dict(cap=5)),
    ('n=4, alltid lägga till', dict(mode='add')),
    ('max 5 + graderad skada', dict(cap=5, graded=5)),
    ('+ kortare våning 3-5', dict(cap=5, graded=5, short=(3, 4, 5))),
    ('+ essoffer', dict(cap=5, graded=5, short=(3, 4, 5), ace_sac=True)),
    ('+ kung värde 22', dict(cap=5, graded=5, short=(3, 4, 5), ace_sac=True, boss_bonus=9)),
    ('+ kungar i två faser', dict(cap=5, graded=5, short=(3, 4, 5), ace_sac=True, boss_twice=True)),
    ('GÄLLANDE: + kungen 3 kort i handen', CURRENT),
    ('Gällande utan jokrar', dict(CURRENT, joker_on=False)),
    ('Gällande utan hjärterläkning', dict(CURRENT, heart_heal=False)),
]

def show(name, res):
    w, dist, by, loops = res
    print(f"{name}\n  vinst {w} %  | per tema ♥{by['H']} ♦{by['D']} ♠{by['S']} ♣{by['C']}  | låsta {loops}")
    print("  förlust per våning:", "  ".join(f"{k}:{v}" for k, v in dist.items()))

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--runs', type=int, default=20000)
    ap.add_argument('--compare', action='store_true')
    for k in ('hand', 'retain', 'lives', 'cap', 'graded', 'boss_hand', 'boss_bonus', 'enemy_bonus'):
        ap.add_argument('--' + k, type=int)
    ap.add_argument('--mode', choices=['choice', 'add', 'swap'])
    a = ap.parse_args()
    if a.compare:
        for name, kw in VARIANTS:
            show(name, stats(N=a.runs, **kw))
    else:
        kw = dict(CURRENT)
        for k in ('hand', 'retain', 'lives', 'cap', 'graded', 'boss_hand', 'boss_bonus', 'enemy_bonus', 'mode'):
            v = getattr(a, k)
            if v is not None: kw[k] = v
        show('Gällande regler' if kw == CURRENT else f'Egen: {kw}', stats(N=a.runs, **kw))
