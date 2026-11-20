"""Fase 3: bitmap finale a piena risoluzione, indici a 16 bit, confinanti e posizioni (castelli, porti, origini).

Uso: python3 fase3_finale.py <regioni_mondo.txt> <EARLY_XL.TXT> <cartella out>
Scrive in <out>/finale/: regioni.png (indice = R + 256 G), regioni.npy (uint16), mondo.json (regioni, confinanti, posizioni).
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

import crescita
import definizioni
import proiezione as P

SEA_FIRST = 1024          # indice della prima zona di mare (la terra parte da 1)
REMOTE_ISLAND_PX = 300    # isole senza seme piu' lontane di cosi' dalla terra con semi: nessuna regione


def nearest_fill(label, valid, target):
    """Assegna a `target` l'etichetta del pixel `valid` piu' vicino."""
    if not target.any():
        return label
    idx = ndimage.distance_transform_edt(~valid, return_distances=False, return_indices=True)
    label[target] = label[idx[0][target], idx[1][target]]
    return label


def pole(mask):
    """Punto interno piu' lontano dal bordo (polo di inaccessibilita' approssimato) e la sua distanza."""
    ys, xs = np.nonzero(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    sub = np.pad(mask[y0:y1, x0:x1], 1)
    dist = ndimage.distance_transform_edt(sub)
    k = np.argmax(dist)
    py, px = np.unravel_index(k, dist.shape)
    return int(px - 1 + x0), int(py - 1 + y0), float(dist.max())


def main(defs_path, startpos_path, out):
    fin = os.path.join(out, 'finale')
    os.makedirs(fin, exist_ok=True)
    defs = definizioni.load(defs_path)
    by_id = {d.id: d for d in defs}
    cmds = definizioni.startpos_commands(startpos_path)
    orig_pairs = definizioni.original_neighbours(cmds)
    land_order = [a[0].upper() for n, a in cmds if n == 'DeclareLandRegion']
    sea_order = [a[0].upper() for n, a in cmds if n == 'DeclareSeaRegion']
    ports_orig = {a[0].upper() for n, a in cmds if n == 'SetPort'}
    idx1 = json.load(open(os.path.join(out, 'indici_fase1.json')))
    id_of1 = {v: k for k, v in idx1.items()}

    # ordine finale: terra europea (ordine dello startpos), terra nuova, mari europei, mari nuovi
    land_ids = land_order + [d.id for d in defs if d.kind == 'TERRA']
    sea_ids = sea_order + [d.id for d in defs if d.kind == 'MARE' and d.id not in sea_order]
    final_index = {rid: 1 + k for k, rid in enumerate(land_ids)}
    final_index.update({rid: SEA_FIRST + k for k, rid in enumerate(sea_ids)})
    lut = np.zeros(max(idx1.values()) + 1, np.uint16)
    for rid, i in idx1.items():
        lut[i] = final_index[rid]

    half = np.load(os.path.join(out, 'etichette_mezza_f2.npy'))
    land = np.load(os.path.join(out, 'terra.npy')).astype(bool)
    H, W = land.shape
    lab = lut[half]
    lab = np.repeat(np.repeat(lab, 2, axis=0), 2, axis=1)[:H, :W].copy()
    if lab.shape != land.shape:
        raise SystemExit('dimensioni diverse %s %s' % (lab.shape, land.shape))
    is_sea_lab = lab >= SEA_FIRST
    # tipo coerente con la costa reale
    good_land = land & (lab > 0) & ~is_sea_lab
    good_sea = ~land & is_sea_lab
    lab = nearest_fill(lab, good_land, land & ~good_land)
    lab = nearest_fill(lab, good_sea, ~land & ~good_sea)
    print('tipo sistemato')

    # isole: semi e componenti connesse
    comp, ncomp = ndimage.label(land)
    seeds_in = {}
    for d in defs:
        if d.is_sea:
            continue
        for la, lo in d.seeds:
            x, y = P.to_px(la, lo)
            xi, yi = int(x) % W, int(np.clip(y, 0, H - 1))
            c = comp[yi, xi]
            if c == 0:
                # seme in acqua (costa approssimata): componente della terra piu' vicina entro 12 px
                win = comp[max(0, yi - 12):yi + 13, max(0, xi - 12):xi + 13]
                vals = win[win > 0]
                if vals.size == 0:
                    continue
                c = np.bincount(vals).argmax()
            seeds_in.setdefault(int(c), set()).add(final_index[d.id])
    sizes = np.bincount(comp.ravel())
    objs = ndimage.find_objects(comp)
    # componenti con semi di piu' regioni: ogni pixel che appartiene a una regione senza seme qui va alla piu' vicina che lo ha
    for c, regs in seeds_in.items():
        sl = objs[c - 1]
        sub = lab[sl]
        m = comp[sl] == c
        allowed = np.isin(sub, np.array(sorted(regs), dtype=np.uint16))
        bad = m & ~allowed
        if bad.any():
            ok = m & allowed
            if ok.any():
                di = ndimage.distance_transform_edt(~ok, return_distances=False, return_indices=True)
                sub[bad] = sub[di[0][bad], di[1][bad]]
                lab[sl] = sub
        if len(regs) == 1:
            sub = lab[sl]
            sub[m] = next(iter(regs))
            lab[sl] = sub
    # componenti senza semi: la regione della terra con semi piu' vicina; troppo lontane: nessuna regione
    seeded = np.isin(comp, np.array(sorted(seeds_in), dtype=np.int64))
    dist_seeded, near_idx = ndimage.distance_transform_edt(~seeded, return_indices=True)
    removed = 0
    for c in range(1, ncomp + 1):
        if c in seeds_in:
            continue
        sl = objs[c - 1]
        m = comp[sl] == c
        sub = lab[sl]
        dsub = dist_seeded[sl]
        if dsub[m].min() > REMOTE_ISLAND_PX:
            sub[m] = 0
            removed += 1
        else:
            iy = near_idx[0][sl][m]
            ix = near_idx[1][sl][m]
            vals = lab[iy, ix]
            sub[m] = np.bincount(vals).argmax()
        lab[sl] = sub
    del near_idx
    print('isole sistemate; remote senza regione:', removed)

    for _ in range(3):
        lab = clean_orphans(lab, defs, final_index, W, H)
    np.save(os.path.join(fin, 'regioni.npy'), lab)
    rgb = np.zeros((H, W, 3), np.uint8)
    rgb[..., 0] = lab & 255
    rgb[..., 1] = lab >> 8
    Image.fromarray(rgb).save(os.path.join(fin, 'regioni.png'), optimize=True)

    # confinanti
    id_of = {v: k for k, v in final_index.items()}
    pairs = crescita.adjacency(lab.astype(np.int32))
    named = {tuple(sorted((id_of[a], id_of[b]))) for a, b in pairs if a in id_of and b in id_of}
    old = set(land_order + sea_order)
    eu_bitmap = {p for p in named if p[0] in old and p[1] in old}
    neighbours = sorted(named | orig_pairs)
    report = {
        'originali': len(orig_pairs),
        'originali_che_non_si_toccano': sorted('%s-%s' % p for p in orig_pairs - eu_bitmap),
        'europei_nuovi_dalla_mappa': sorted('%s-%s' % p for p in eu_bitmap - orig_pairs),
        'totale': len(neighbours),
    }

    # posizioni
    ys_all = None
    regions = []
    objs_lab = ndimage.find_objects(lab.astype(np.int32))
    sea_adj = {}
    for a, b in neighbours:
        sea_adj.setdefault(a, set()).add(b)
        sea_adj.setdefault(b, set()).add(a)
    for rid in land_ids + sea_ids:
        i = final_index[rid]
        sl = objs_lab[i - 1] if i - 1 < len(objs_lab) else None
        if sl is None:
            print('REGIONE SENZA PIXEL', rid)
            continue
        m = lab[sl] == i
        # regioni a cavallo della cucitura: si lavora sul pezzo piu' grande
        cl, n = ndimage.label(m)
        if n > 1:
            big = np.bincount(cl.ravel())[1:].argmax() + 1
            mbig = cl == big
        else:
            mbig = m
        ox, oy = sl[1].start, sl[0].start
        px, py, depth = pole(mbig)
        info = {'id': rid, 'index': i, 'sea': rid in sea_ids, 'pixels': int(m.sum()),
                'origin': [px + ox, py + oy]}
        d = by_id.get(rid)
        if not info['sea']:
            # castello: citta' reale se cade nella regione (o entro 20 px), altrimenti il polo interno
            cx, cy = P.to_px(*d.castle)
            cx, cy = int(cx) % W, int(cy)
            if lab[cy, cx] != i:
                yy, xx = np.nonzero(mbig)
                dd = (yy + oy - cy) ** 2 + (xx + ox - cx) ** 2
                k = int(np.argmin(dd))
                if dd[k] <= 20 * 20:
                    cx, cy = int(xx[k] + ox), int(yy[k] + oy)
                else:
                    cx, cy = px + ox, py + oy
            info['castle'] = [cx, cy]
            # porto: regioni costiere (originali solo se avevano SetPort)
            coast_seas = [s for s in sea_adj.get(rid, ()) if s in sea_ids]
            can_port = (rid in ports_orig) if rid in land_order else bool(coast_seas)
            if can_port and coast_seas:
                info['port'] = port_position(lab, i, [final_index[s] for s in coast_seas], cx, cy, W, H)
        regions.append(info)
    json.dump({'width': W, 'height': H, 'sea_first': SEA_FIRST, 'regions': regions,
               'neighbours': neighbours, 'report': report,
               'projection': {'lon_left': P.LON_LEFT, 'lat_top': P.LAT_TOP, 'lat_bottom': P.LAT_BOTTOM, 'scale': P.SCALE}},
              open(os.path.join(fin, 'mondo.json'), 'w'), indent=1)
    print('confinanti', len(neighbours), 'originali senza contatto', len(report['originali_che_non_si_toccano']),
          'nuovi europei', len(report['europei_nuovi_dalla_mappa']))


def clean_orphans(lab, defs, final_index, W, H):
    """Pezzi staccati di una regione senza semi (resti della deformazione): vanno alla regione confinante piu' vicina.
    Si tiene sempre il pezzo piu' grande; le isolette lontane dalla terra della regione restano a chi e' piu' vicino."""
    seed_pts = {}
    for d in defs:
        pts = []
        for la, lo in d.seeds + ([d.castle] if d.castle else []):
            x, y = P.to_px(la, lo)
            pts.append((int(np.clip(y, 0, H - 1)), int(x) % W))
        seed_pts[final_index[d.id]] = pts
    objs = ndimage.find_objects(lab.astype(np.int32))
    orphan = np.zeros(lab.shape, bool)
    for i, sl in enumerate(objs, start=1):
        if sl is None:
            continue
        m = lab[sl] == i
        pieces, n = ndimage.label(m)
        if n <= 1:
            continue
        sizes = np.bincount(pieces.ravel())
        sizes[0] = 0
        keep = {int(sizes.argmax())}
        for (py, px) in seed_pts.get(i, []):
            ly, lx = py - sl[0].start, px - sl[1].start
            if 0 <= ly < m.shape[0] and 0 <= lx < m.shape[1]:
                # pezzo con il seme o il piu' vicino al seme (entro 6 px)
                win = pieces[max(0, ly - 6):ly + 7, max(0, lx - 6):lx + 7]
                vals = win[win > 0]
                if vals.size:
                    keep.add(int(np.bincount(vals).argmax()))
        bad = (pieces > 0) & ~np.isin(pieces, np.array(sorted(keep)))
        # solo i pezzi che toccano un'altra regione dello stesso tipo (le isolette circondate dal mare restano)
        o = orphan[sl]
        o |= bad
        orphan[sl] = o
    land_like = (lab > 0) & (lab < SEA_FIRST)
    # le isolette (pezzi circondati solo dal mare) non sono orfane: tengono l'etichetta scelta prima
    comp, _ = ndimage.label(land_like)
    for want_land in (True, False):
        cls = land_like if want_land else (lab >= SEA_FIRST)
        o = orphan & cls
        if not o.any():
            continue
        if want_land:
            # orfano su terra: solo se il suo pezzo tocca terra di un'altra regione (altrimenti e' un'isola a se')
            grown = ndimage.binary_dilation(o, iterations=1) & cls & ~o
            touched = np.unique(comp[grown])
            o &= np.isin(comp, touched)
        valid = cls & ~o
        lab = nearest_fill(lab, valid, o)
    return lab


def port_position(lab, i, sea_idx, cx, cy, W, H, radius=160):
    """Pixel d'acqua di una zona di mare confinante, sulla costa della regione, il piu' vicino al castello."""
    y0, y1 = max(0, cy - radius), min(H, cy + radius)
    xs = np.arange(cx - radius, cx + radius) % W
    win = lab[y0:y1][:, xs]
    region = win == i
    sea = np.isin(win, np.array(sea_idx, dtype=np.uint16))
    coast = sea & ndimage.binary_dilation(region, iterations=2)
    if not coast.any():
        if radius < 2000:
            return port_position(lab, i, sea_idx, cx, cy, W, H, radius * 3)
        return None
    yy, xx = np.nonzero(coast)
    dd = (yy + y0 - cy) ** 2 + (xs[xx] - cx) ** 2
    k = int(np.argmin(dd))
    return [int(xs[xx[k]]), int(yy[k] + y0)]


if __name__ == '__main__':
    main(*sys.argv[1:4])
