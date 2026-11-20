"""Dati dell'isola di Atlantide (ADR-078): variante della bitmap con i 5 territori, righe dello startpos, voci di mondo.json.

Uso: python3 atlantide_dati.py <cartella out>
Legge out/finale/regioni.npy e mondo.json; scrive regioni_auror.npy/.png, startpos_atlantide.txt e aggiunge a mondo.json
le regioni dell'isola (con "auror": true) e i loro confinanti in "neighbours_auror".
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

import atlantide as A
import crescita
import proiezione as P
from fase3_finale import pole, port_position
from genera_startpos import port_direction

S = P.STARTPOS_SCALE
# Tutte le merci (DeclareTradegoods dello startpos XL) e tutti i giacimenti in ogni territorio (richiesta di Federico del
# 16/11/2026: «le 5 regioni di Atlantide devono avere tutte le risorse e materie prime possibili»), come le regioni degli
# Auror nella mod. La rendita resta quella di prima: Atlantide 1200, gli altri 600.
ALL_GOODS = ['GLASSWARE', 'WOOD', 'FURS', 'WINE', 'WOOL', 'SILK', 'COTTON', 'LINEN', 'WAX', 'HONEY', 'SALT', 'HIDES',
             'BUTTER', 'POTTERY', 'FISH', 'SPICES', 'GEMS', 'SUGAR', 'DYES', 'IVORY', 'OLIVEOIL', 'GRAIN', 'WHALEBONE',
             'PEWTER']
ALL_RESOURCES = ['IRON', 'COPPER', 'SILVER', 'GOLD', 'SALT']
ATTR = {rid: (1200 if rid == 'ID_ATLANTIS' else 600, ALL_GOODS, ALL_RESOURCES)
        for rid in ('ID_ATLANTIS', 'ID_GADEIRA', 'ID_AMPHERIA', 'ID_MNESEIA', 'ID_DIAPREPIA')}


def main(out):
    fin = os.path.join(out, 'finale')
    lab = np.load(os.path.join(fin, 'regioni.npy'))
    mondo = json.load(open(os.path.join(fin, 'mondo.json')))
    regions = [r for r in mondo['regions'] if not r.get('auror')]
    H, W = lab.shape
    land_max = max(r['index'] for r in regions if not r['sea'])
    ids = [t[0] for t in A.TERRITORIES]
    index = {rid: land_max + 1 + k for k, rid in enumerate(ids)}
    cx, cy = A.center_px()
    hx, hy = A.HALF_BOX
    ya, yb, xa, xb = int(cy - hy), int(cy + hy), int(cx - hx), int(cx + hx)
    yy, xx = np.mgrid[ya:yb, xa:xb]
    X, Y = xx + 0.5, yy + 0.5
    terr = A.territory(X, Y)
    # canale verso sud: fa parte di Atlantide e le da' il porto
    canal = (np.abs(X - cx) <= 3.0 * A.SCALE) & (Y > cy) & (terr >= 0)
    terr = np.where(canal, 0, terr)
    sub = lab[ya:yb, xa:xb].copy()
    if (sub[terr >= 0] < 1024).any():
        raise SystemExit("l'isola copre terra esistente")
    for k, rid in enumerate(ids):
        sub[terr == k] = index[rid]
    lab_a = lab.copy()
    lab_a[ya:yb, xa:xb] = sub
    np.save(os.path.join(fin, 'regioni_auror.npy'), lab_a)
    rgb = np.zeros((H, W, 3), np.uint8)
    rgb[..., 0] = lab_a & 255
    rgb[..., 1] = lab_a >> 8
    Image.fromarray(rgb).save(os.path.join(fin, 'regioni_auror.png'), optimize=True)

    id_of = {r['index']: r['id'] for r in regions}
    id_of.update({v: k for k, v in index.items()})
    pairs = crescita.adjacency(sub.astype(np.int32), wrap=False)
    nb = sorted({tuple(sorted((id_of[a], id_of[b]))) for a, b in pairs if (a in index.values() or b in index.values())})
    new_regions = []
    L = ['// Isola di Atlantide (ADR-078), solo in modalita\' Auror. Generato da tools/mondo/atlantide_dati.py.',
         '// Proprietari, edifici ed eserciti degli Auror li sposta il codice (AtlantisScenario) dallo startpos dell\'installazione.']
    for rid in ids:
        L.append('DeclareLandRegion::\t"%s"' % rid)
    for k, (rid, it, en, _) in enumerate(A.TERRITORIES):
        m = sub == index[rid]
        px, py, _ = pole(m)
        gx, gy = px + xa, py + ya
        if rid == 'ID_ATLANTIS':
            gx, gy = int(cx), int(cy)
        income, goods, res = ATTR[rid]
        seas = [b if a == rid else a for a, b in nb if rid in (a, b)]
        seas = [s for s in seas if s not in index]
        info = {'id': rid, 'index': index[rid], 'sea': False, 'auror': True, 'pixels': int(m.sum()),
                'origin': [gx, gy], 'castle': [gx, gy], 'it': it, 'en': en}
        if seas:
            sea_idx = [next(r['index'] for r in regions if r['id'] == s) for s in seas]
            port = port_position(lab_a, index[rid], sea_idx, gx, gy, W, H)
            info['port'] = port
        new_regions.append(info)
        L.append('SetAttributes::\t%s\t"%s"\t0\tCATHOLIC_CULTURE\tLUSH\tAT_WESTERN_EUROPEAN\t-1\t%d\t"%s Castle"\t%s\tHILLY\tNO_RIVER\tTRUE'
                 % (rid, en, income, en, 'COAST' if seas else 'INLAND'))
        L.append('SetRegionRebels::\t%s\t62' % rid)
        L.append('AddTitle::\t%s\t"Lord of %s"\t+1\t0\t0\t0\t0\t0\t0' % (rid, en))
        L.append('SetTradableGoods::\t%s\t%s' % (rid, '\t'.join(goods)))
        L.append('SetResources::\t%s\t%s' % (rid, '\t'.join(res)))
        L.append('SetCastle::\t%s\t%d\t%d' % (rid, gx * S + S // 2, gy * S + S // 2))
        if info.get('port'):
            ppx, ppy = info['port']
            L.append('SetPort::\t%s\t%d\t%d\t%d' % (rid, ppx * S + S // 2, ppy * S + S // 2, port_direction(lab_a, ppx, ppy)))
    by = {}
    for a, b in nb:
        by.setdefault(a, []).append(b)
        by.setdefault(b, []).append(a)
    for rid in ids:
        L.append('SetNeighbours::\t%s\t%s' % (rid, '\t'.join(sorted(by[rid]))))
    for rid, lst in sorted(by.items()):
        if rid in index:
            continue
        L.append('SetNeighbours::\t%s\t%s' % (rid, '\t'.join(sorted(x for x in lst if x in index))))
    open(os.path.join(fin, 'startpos_atlantide.txt'), 'w', encoding='latin-1', newline='\r\n').write('\n'.join(L) + '\n')
    mondo['regions'] = regions + new_regions
    mondo['neighbours_auror'] = nb
    json.dump(mondo, open(os.path.join(fin, 'mondo.json'), 'w'), indent=1)
    print('isola: confinanti', nb)
    print({r['id']: (r['pixels'], r.get('port')) for r in new_regions})
    # nomi
    open(os.path.join(fin, 'nomi_atlantide.cfg'), 'w', encoding='utf-8').write(
        '\n'.join(['[terra]'] + ['%s="%s"' % (t[0], t[1]) for t in A.TERRITORIES]) + '\n')
    open(os.path.join(fin, 'nomi_atlantide_en.tsv'), 'w', encoding='utf-8').write(
        '\n'.join('%s\t%s' % (t[1], t[2]) for t in A.TERRITORIES if t[1] != t[2]) + '\n')


if __name__ == '__main__':
    main(sys.argv[1])
