"""Collega LukMap.Lbm alle regioni dello startpos e deriva adiacenze di prova.
Uso: python3 -I lbm_regions.py <startpos> <index.npy> <outdir>"""
import sys, re, json, collections
import numpy as np
from scipy import ndimage
sp = open(sys.argv[1], encoding='cp1252').read().replace('\r', '')
idx = np.load(sys.argv[2]); outdir = sys.argv[3]
H, W = idx.shape
land = re.findall(r'^DeclareLandRegion::\s+"(\w+)"', sp, re.M)
sea = re.findall(r'^DeclareSeaRegion::\s+"(\w+)"', sp, re.M)
allr = land + sea
castle = {m.group(1): (int(m.group(2)), int(m.group(3))) for m in re.finditer(r'^SetCastle::\s+(\w+)\s+(\d+)\s+(\d+)', sp, re.M)}
origin = {m.group(1): (int(m.group(2)), int(m.group(3))) for m in re.finditer(r'^SetOrigin::\s+(\w+)\s+(\d+)\s+(\d+)', sp, re.M)}
neigh = {}
for m in re.finditer(r'^SetNeighbours::\s+(.*)$', sp, re.M):
    t = m.group(1).split(); neigh[t[0]] = t[1:]
# 1) scala coordinate -> pixel: prova divisori
res = {}
for div in (8, 16, 32):
    ok = 0; tot = 0; ids = collections.defaultdict(collections.Counter)
    for r, (x, y) in castle.items():
        px, py = x//div, y//div
        if 0 <= px < W and 0 <= py < H:
            ids[r][int(idx[py, px])] += 1; tot += 1
    res[div] = ids
    print('div', div, 'castelli dentro mappa', tot)
div = 16
c2i = {r: list(res[div][r].keys())[0] for r in res[div]}
# indice unico per regione? (castello) - verifica monotonia con l'ordine di dichiarazione
pairs = [(allr.index(r), c2i[r]) for r in land if r in c2i]
print('esempio (ordine dichiarazione, indice palette al castello):', pairs[:30])
# 2) origine delle regioni di mare
o2i = {}
for r, (x, y) in origin.items():
    px, py = x//div, y//div
    if 0 <= px < W and 0 <= py < H: o2i[r] = int(idx[py, px])
json.dump({'castle_idx': c2i, 'origin_idx': o2i}, open(outdir + '/region_probe.json', 'w'), indent=1)
