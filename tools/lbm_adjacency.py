"""Ricava adiacenze dalla bitmap LukMap (idx>>1 = ordine regione terra; 216+k = mare k)
e le confronta con SetNeighbours dello startpos.
Uso: python3 -I lbm_adjacency.py <startpos> <index.npy> <outdir> [raggio_ponte_px]"""
import sys, re, json, itertools, collections
import numpy as np
from scipy import ndimage
sp = open(sys.argv[1], encoding='cp1252').read().replace('\r', '')
idx = np.load(sys.argv[2]); outdir = sys.argv[3]
R = int(sys.argv[4]) if len(sys.argv) > 4 else 3
land = re.findall(r'^DeclareLandRegion::\s+"(\w+)"', sp, re.M)
sea = re.findall(r'^DeclareSeaRegion::\s+"(\w+)"', sp, re.M)
def rid(v):
    if v < 2: return None
    if v < 216: return land[v//2 - 1] if v//2 - 1 < len(land) else None
    k = v - 216
    return sea[k] if k < len(sea) else None
# etichetta per regione (mappa a indice regione 0..142, -1 = nessuna)
lut = np.full(256, -1, dtype=np.int16)
names = land + sea
for v in range(2, 252):
    n = rid(v)
    if n: lut[v] = names.index(n)
reg = lut[idx]
# 1) adiacenza diretta (4-vicini)
pairs = collections.Counter()
def add(a, b):
    m = (a != b) & (a >= 0) & (b >= 0)
    for x, y in zip(a[m], b[m]): pairs[(min(x, y), max(x, y))] += 1
add(reg[:, :-1], reg[:, 1:]); add(reg[:-1, :], reg[1:, :])
direct = dict(pairs)
# 2) ponte sui pixel senza regione (bordi indice 0): per ogni pixel -1 guarda in finestra (2R+1) le etichette vicine
pairs2 = collections.Counter()
if R > 0:
    for dy in range(-R, R+1):
        for dx in range(-R, R+1):
            if dx == 0 and dy == 0: continue
            a = reg[max(0,-dy):reg.shape[0]-max(0,dy), max(0,-dx):reg.shape[1]-max(0,dx)]
            b = reg[max(0,dy):reg.shape[0]-max(0,-dy) if dy<0 else reg.shape[0], max(0,dx):reg.shape[1]-max(0,-dx) if dx<0 else reg.shape[1]]
            h = min(a.shape[0], b.shape[0]); w = min(a.shape[1], b.shape[1])
            a = a[:h,:w]; b = b[:h,:w]
            m = (a != b) & (a >= 0) & (b >= 0)
            u = np.unique(np.stack([np.minimum(a[m], b[m]), np.maximum(a[m], b[m])], 1), axis=0, return_counts=True)
            for (x, y), c in zip(*u): pairs2[(int(x), int(y))] += int(c)
# riferimento SetNeighbours
ref = set()
for m in re.finditer(r'^SetNeighbours::\s+(.*)$', sp, re.M):
    t = m.group(1).split()
    for o in t[1:]:
        if t[0] in names and o in names: ref.add(tuple(sorted((names.index(t[0]), names.index(o)))))
def stats(cand, label, minpx=1):
    c = {p for p, n in cand.items() if n >= minpx}
    tp = len(c & ref); fp = len(c - ref); fn = len(ref - c)
    print(f'{label} minpx={minpx}: trovate={len(c)} corrette={tp} extra(FP)={fp} mancanti(FN)={fn} precisione={tp/max(1,len(c)):.2f} richiamo={tp/len(ref):.2f}')
    return c
print('coppie di riferimento (SetNeighbours, non orientate):', len(ref))
for mp in (1, 5, 20, 50):
    stats(direct, 'diretta', mp)
for mp in (1, 20, 100, 400):
    stats(pairs2, f'ponte R={R}', mp)
c = {p for p, n in pairs2.items() if n >= 100}
json.dump({'ref': sorted(map(list, ref)), 'bitmap_R%d_min100' % R: sorted(map(list, c)), 'names': names,
           'extra_fp': [[names[a], names[b], pairs2[(a,b)]] for a, b in sorted(c - ref)],
           'missing_fn': [[names[a], names[b], pairs2.get((a,b),0)] for a, b in sorted(ref - c)]},
          open(outdir + '/adjacency_compare.json', 'w'), indent=0)
print('FP (primi 25):', [[names[a], names[b], pairs2[(a,b)]] for a, b in sorted(c - ref)][:25])
print('FN (primi 25):', [[names[a], names[b], pairs2.get((a,b),0)] for a, b in sorted(ref - c)][:25])
