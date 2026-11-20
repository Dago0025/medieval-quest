"""Righe dello startpos per la mappa del mondo (ADR-077) e nomi delle regioni nuove.

Uso: python3 genera_startpos.py <regioni_mondo.txt> <EARLY_XL.TXT> <mondo.json> <cartella uscita>
Scrive:
- startpos_mondo.txt: regioni nuove (dichiarazioni, attributi, guarnigioni ribelli, merci) e, per tutte le regioni,
  castelli, origini, porti e confinanti nella geometria del mondo. Il caricatore toglie dallo startpos originale le righe
  SetNeighbours, SetCastle, SetOrigin, SetPort e SetBorderInfo e aggiunge queste.
- nomi_mondo.cfg: [terra] e [mare] con i nomi italiani delle regioni nuove (da unire a data/province.cfg)
- nomi_mondo_en.tsv: nomi inglesi (chiave = nome italiano, come data/lingue/en.tsv)
"""
import json
import math
import os
import sys

import numpy as np

import definizioni
import proiezione as P

S = P.STARTPOS_SCALE


def port_direction(lab, px, py, sea_first=1024, r=10):
    """Orientamento del molo (fotogramma di campmap/ships/port.BIF) dalla direzione del mare attorno al porto.
    Ricavato dai 71 porti dello startpos sulla LukMap: con `a` = direzione del mare in gradi da nord in senso orario,
    il fotogramma e' circa (120 - a) / 45 (1 = mare a nord-est, 3 = nord-nord-ovest, 5 = ovest-sud-ovest, 7 = sud-sud-est)."""
    h, w = lab.shape
    ys, xs = np.mgrid[-r:r + 1, -r:r + 1]
    yy = np.clip(py + ys, 0, h - 1)
    xx = (px + xs) % w
    sea = lab[yy, xx] >= sea_first
    vx = float((xs * sea).sum() - (xs * ~sea).sum())
    vy = float((ys * sea).sum() - (ys * ~sea).sum())
    ang = math.degrees(math.atan2(vx, -vy)) % 360.0
    return int(round((120.0 - ang) / 45.0)) % 8


def main(defs_path, startpos_path, mondo_path, outdir):
    os.makedirs(outdir, exist_ok=True)
    defs = definizioni.load(defs_path)
    by_id = {d.id: d for d in defs}
    mondo = json.load(open(mondo_path))
    regs = {r['id']: r for r in mondo['regions']}
    cmds = definizioni.startpos_commands(startpos_path)
    lab = np.load(os.path.join(os.path.dirname(mondo_path), 'regioni.npy'))
    L = []
    w = L.append
    w('// Mappa del mondo di Medieval Quest (ADR-077). Generato da tools/mondo/genera_startpos.py: non modificare a mano.')
    w('// Il caricatore toglie dallo startpos originale SetNeighbours, SetCastle, SetOrigin, SetPort e SetBorderInfo.')
    w('')
    new_land = [d for d in defs if d.kind == 'TERRA']
    new_sea = [d for d in defs if d.kind == 'MARE' and d.it]
    w('// ---- regioni nuove')
    for d in new_land:
        w('DeclareLandRegion::\t"%s"' % d.id)
    for d in new_sea:
        w('DeclareSeaRegion::\t"%s"' % d.id)
    w('')
    w('// ---- attributi delle regioni nuove (ribelli all\'inizio)')
    for d in new_land:
        r = regs[d.id]
        coast = 'COAST' if r.get('port') else 'INLAND'
        view = {'ROCK_DESERT': 'HILLY', 'SAND_DESERT': 'FLAT'}.get(d.terrain, 'PLAINS')
        rebellious = 1 if d.culture == 'PAGAN' else 0
        w('SetAttributes::\t%s\t"%s"\t%d\t%s_CULTURE\t%s\t%s\t-1\t%d\t"%s Castle"\t%s\t%s\tNO_RIVER\tTRUE'
          % (d.id, d.en, rebellious, d.culture, d.terrain, d.arch, d.income, d.en, coast, view))
    goods_ok = {a[0].upper() for n, a in cmds if n == 'DeclareTradegoods'}
    for d in new_land:
        res = list(dict.fromkeys(d.resources + [g for g in d.goods if g in ('GOLD', 'SILVER', 'IRON', 'COPPER')]))
        bad = [g for g in d.goods if g not in goods_ok and g not in res]
        if bad:
            raise SystemExit('merci sconosciute in %s: %s' % (d.id, bad))
        d.goods = [g for g in d.goods if g in goods_ok]
        d.resources = res
    for d in new_land:
        w('SetRegionRebels::\t%s\t%d' % (d.id, d.rebels))
        w('AddTitle::\t%s\t"Governor of %s"\t+1\t0\t0\t0\t0\t0\t0' % (d.id, d.en))
        if d.goods:
            w('SetTradableGoods::\t%s\t%s' % (d.id, '\t'.join(d.goods)))
        if d.resources:
            w('SetResources::\t%s\t%s' % (d.id, '\t'.join(d.resources)))
        w('MakeBuilding::\t%s\t%s' % (d.id, 'Castle3' if d.income >= 600 else 'Castle2'))
        if d.income >= 450:
            w('MakeBuilding::\t%s\tImproved_farmland' % d.id)
        for unit, men in d.garrison:
            w('MakeUnit::\t%s\t%s\t%d\t%s_CULTURE' % (d.id, unit, men, d.culture))
    w('')
    w('// ---- posizioni nella geometria del mondo (pixel x %d)' % S)
    regions = [r for r in mondo['regions'] if not r.get('auror')]   # l'isola di Atlantide ha le sue righe (ADR-078)
    for r in regions:
        if not r['sea']:
            cx, cy = r['castle']
            w('SetCastle::\t%s\t%d\t%d' % (r['id'], cx * S + S // 2, cy * S + S // 2))
    for r in regions:
        ox, oy = r['origin']
        w('SetOrigin::\t%s\t%d\t%d' % (r['id'], ox * S + S // 2, oy * S + S // 2))
    for r in regions:
        if r['sea'] or not r.get('port'):
            continue
        px, py = r['port']
        cx, cy = r['castle']
        # orientamento ricalcolato anche per i porti europei: la costa del mondo non e' quella della LukMap
        direction = port_direction(lab, px, py)
        w('SetPort::\t%s\t%d\t%d\t%d' % (r['id'], px * S + S // 2, py * S + S // 2, direction))
    w('')
    w('// ---- confinanti: contatti della mappa del mondo piu\' tutti quelli dello startpos originale')
    nb = {}
    for a, b in mondo['neighbours']:
        nb.setdefault(a, []).append(b)
        nb.setdefault(b, []).append(a)
    for r in regions:
        rid = r['id']
        if rid in nb:
            w('SetNeighbours::\t%s\t%s' % (rid, '\t'.join(sorted(nb[rid]))))
    open(os.path.join(outdir, 'startpos_mondo.txt'), 'w', encoding='latin-1', newline='\r\n').write('\n'.join(L) + '\n')
    # nomi
    it = ['; Nomi italiani delle regioni della mappa del mondo (ADR-077). Generato da tools/mondo/genera_startpos.py.', '[terra]']
    it += ['%s="%s"' % (d.id, d.it) for d in new_land]
    it += ['[mare]'] + ['%s="%s"' % (d.id, d.it) for d in new_sea]
    open(os.path.join(outdir, 'nomi_mondo.cfg'), 'w', encoding='utf-8').write('\n'.join(it) + '\n')
    en = ['%s\t%s' % (d.it, d.en) for d in new_land + new_sea if d.it != d.en]
    open(os.path.join(outdir, 'nomi_mondo_en.tsv'), 'w', encoding='utf-8').write('\n'.join(en) + '\n')
    print('regioni nuove', len(new_land), 'mari nuovi', len(new_sea), 'righe', len(L))


if __name__ == '__main__':
    main(*sys.argv[1:5])
