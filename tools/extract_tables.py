"""Estrae tabelle CSV (regioni, unita, edifici, fazioni) dai file MTW XL. Solo lettura.
Uso: python3 -I extract_tables.py <cartella_gioco> <outdir>"""
import sys, os, re, csv, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tsvload
G, O = sys.argv[1], sys.argv[2]; os.makedirs(O, exist_ok=True)
cl = lambda s: ' '.join(s.split())
sp = open(os.path.join(G, 'campmap/startpos/EARLY_XL.TXT'), encoding='cp1252').read().replace('\r', '')
code = lambda l: l.split('//')[0]
lines = sp.split('\n')
def cmds(name): return [code(l).split() for l in lines if re.match(r'^\s*' + name + '::', l)]
land = [c[1].strip('"') for c in cmds('DeclareLandRegion')]
facs = [c[1].strip('"') for c in cmds('DeclareFaction')]
own = {c[1]: c[2] for c in cmds('SetRegionOwner')}
castle = {c[1]: c[2:4] for c in cmds('SetCastle')}; port = {c[1]: c[2:5] for c in cmds('SetPort')}
reb = {c[1]: c[2] for c in cmds('SetRegionRebels')}
res = collections.defaultdict(list); goods = collections.defaultdict(list)
for c in cmds('SetResources'): res[c[1]] += c[2:]
for c in cmds('SetTradableGoods'): goods[c[1]] += c[2:]
bld = collections.defaultdict(list)
for c in cmds('MakeBuilding'): bld[c[1]].append(c[2])
with open(os.path.join(O, 'regions.csv'), 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['ordine0', 'id', 'nome', 'rebellious', 'cultura', 'terreno', 'architettura', 'income', 'castello', 'location', 'vista', 'fiume', 'owner', 'rebelfaction_idx', 'castle_x', 'castle_y', 'port', 'risorse', 'merci', 'n_edifici_iniziali'])
    for l in lines:
        m = re.match(r'^SetAttributes::\s+(\w+)\s+"([^"]*)"\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+"([^"]*)"\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)', l)
        if not m: continue
        g = m.groups(); r = g[0]
        w.writerow([land.index(r), r, g[1], g[2], g[3], g[4], g[5], g[7], g[8], g[9], g[10], g[11], own.get(r, 'REBEL'), reb.get(r, ''), *castle.get(r, ['', '']), ' '.join(port.get(r, [])), ' '.join(res[r]), ' '.join(goods[r]), len(bld[r])])
U = tsvload.load(os.path.join(G, 'MTW_XL_EARLY_UNIT_PROD11.TXT'))
def st(r, k):
    m = re.search(k + r'\(\s*(-?[\d.]+)\s*\)', r[21]); return m.group(1) if m else ''
with open(os.path.join(O, 'units_early.csv'), 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['nome', 'tipo', 'costo', 'supporto', 'tempo_stagioni', 'uomini', 'honour_step', 'armour', 'honour_lvl', 'charge', 'melee', 'defence', 'ammo', 'proiettile', 'edifici', 'periodi', 'n_fazioni', 'regioni', 'culture'])
    for r in U[4:]:
        if not r or not r[0].strip(): continue
        fa = cl(r[28]); n = 'ALL' if fa in ('ALL_FACTIONS', '') else len(re.findall(r'FN_\w+', fa))
        w.writerow([r[0].strip(), r[1], r[2], r[3], r[4], r[7], r[8], st(r, 'ARMOUR_LEVEL'), st(r, 'HONOUR_LEVEL'), st(r, 'CHARGE_BONUS'), st(r, 'MELEE_BONUS'), st(r, 'DEFENCE_BONUS'), st(r, 'AMMO'), (re.search(r'PROJECTILE_TYPE\(\s*(\w+)', r[21]) or [0, ''])[1], cl(r[16]), cl(r[19]), n, cl(r[29]), cl(r[32])])
B = tsvload.load(os.path.join(G, 'MTW_XL_EARLY_BUILD_PROD13.TXT'))
with open(os.path.join(O, 'buildings_early.csv'), 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['nome', 'livelli', 'tipo', 'costi', 'tempi', 'condizioni', 'religione', 'tech', 'risorse', 'reddito', 'felicita', 'capacita', 'invenzioni'])
    for r in B[4:]:
        if not r or not r[0].strip(): continue
        w.writerow([r[1], int(r[0]) + 1, cl(r[3]), cl(r[4]), cl(r[5]), cl(r[6]), cl(r[14]), cl(r[17]), cl(r[18]), cl(r[22]), cl(r[23]), cl(r[27]), cl(r[26])])
leaders = {c[1]: c[2:] for c in cmds('SetStartLeader')}; where = {c[2]: c[1] for c in cmds('PlaceLeader')}
heirs = collections.Counter(c[1] for c in cmds('AddHeir')); act = {c[1]: c[2] for c in cmds('SetActiveFaction')}
cul = {c[1]: c[2] for c in cmds('SetCulture')}; rel = {c[1]: c[2] for c in cmds('SetReligion')}; beh = {c[1]: c[2] for c in cmds('SetBehaviour')}
tre = {c[1]: c[2:] for c in cmds('SetTreasury')}
with open(os.path.join(O, 'factions.csv'), 'w', newline='') as f:
    w = csv.writer(f); w.writerow(['id', 'ordine0', 'attiva', 'cultura', 'religione', 'comportamento', 'tesoro_e_n_h_x', 'capitale_leader', 'regioni_iniziali', 'eredi', 'start_leader_args'])
    for i, fa in enumerate(facs):
        w.writerow([fa, i, act.get(fa, 'NO'), cul.get(fa, ''), rel.get(fa, ''), beh.get(fa, ''), '/'.join(tre.get(fa, [])), where.get(fa, ''), len([r for r, o in own.items() if o == fa]), heirs[fa], ' '.join(leaders.get(fa, []))])
print('ok')
