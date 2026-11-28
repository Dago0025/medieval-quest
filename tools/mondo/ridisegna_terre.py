"""Ridisegna le regioni di terra fuori Europa sulla bitmap finale (28/11/2026, richiesta di Federico: «migliorare i confini
dei territori terrestri e frammentare un po' di piu' gli altri continenti»).

L'Europa (le 107 province della LukMap), le zone di mare (gia' unite da unisci_mari.py) e l'isola di Atlantide restano
pixel per pixel come sono: si rifanno solo i pixel che oggi appartengono alle regioni TERRA di regioni_mondo.txt, con i
semi di tutte le regioni TERRA (le 121 di prima con i semi aggiornati e le 100 di nuove_regioni.py).

Confini naturali: la crescita dai semi (crescita.grow, come la fase 1) usa un costo che
- sale con la pendenza del rilievo (i crinali fermano la crescita: i confini passano sulle creste);
- sale molto sui fiumi principali di Natural Earth (scalerank <= 6): le regioni si fermano sulle rive e i confini corrono
  lungo i fiumi invece di tagliarli;
- e' moltiplicato per un rumore frattale a piu' scale, cosi' i tratti di pianura non escono dritti come in un Voronoi.

Scrive in <uscita>: regioni.png, regioni_auror.png, regioni.npy, regioni_auror.npy, mondo.json (posizioni, pixel,
etichette e indici delle regioni TERRA; le altre voci come prima), startpos_mondo.txt (dichiarazioni e attributi delle
regioni nuove, castelli, origini e porti delle regioni TERRA, confinanti ricalcolati), nomi_terra.cfg (nomi italiani) e
un'anteprima.

Uso: python3 ridisegna_terre.py <regioni_mondo.txt> <cartella data/mappa_mondo> <cartella geo> <uscita>
"""
import json
import os
import re
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import crescita
import definizioni
import fase3_finale as F3
import genera_startpos as GS
import proiezione as P
from fase1_regioni import elevation_grid, snap

HALF = 2
SEA_FIRST = 1024
RIVER_RANK = 6          # fiumi di Natural Earth con scalerank fino a questo
RIVER_COST = 14.0       # costo in piu' per pixel di fiume (mezza risoluzione)
SLOPE_COST = 90.0       # peso della pendenza
NOISE_AMP = 0.55        # ampiezza del rumore (logaritmo del moltiplicatore)
EUROPA = os.environ.get('EUROPA', '') == '1'
EU_ROUNDS = 4          # giri di correzione delle velocita' delle province europee
WARP_AMP = 9.0          # spostamento del domain warping (pixel a mezza risoluzione, deviazione standard)


def read_index(path):
    img = np.asarray(Image.open(path).convert('RGB'))
    return img[..., 0].astype(np.uint16) + 256 * img[..., 1].astype(np.uint16)


def write_index(path, lab):
    rgb = np.zeros(lab.shape + (3,), np.uint8)
    rgb[..., 0] = lab & 255
    rgb[..., 1] = lab >> 8
    Image.fromarray(rgb).save(path, optimize=True)


def fractal_noise(h, w, seed=11):
    rng = np.random.default_rng(seed)
    total = np.zeros((h, w), np.float32)
    amp_sum = 0.0
    for scale, amp in ((90, 1.0), (36, 0.6), (14, 0.35), (6, 0.2)):
        g = rng.standard_normal((h // scale + 3, w // scale + 3)).astype(np.float32)
        up = np.asarray(Image.fromarray(g).resize(((w // scale + 3) * scale, (h // scale + 3) * scale), Image.BICUBIC))
        total += amp * up[:h, :w]
        amp_sum += amp
    total /= amp_sum
    return total / max(1e-6, float(np.abs(total).max()))


def river_mask(geo, h, w):
    data = json.load(open(os.path.join(geo, 'ne_10m_rivers_lake_centerlines.geojson'), encoding='utf-8'))
    img = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(img)
    for f in data['features']:
        rank = f['properties'].get('scalerank')
        if rank is None or rank > RIVER_RANK:
            continue
        g = f['geometry']
        lines = g['coordinates'] if g['type'] == 'MultiLineString' else [g['coordinates']]
        for line in lines:
            pts = np.asarray(line, dtype=np.float64)
            x, y = P.to_px(pts[:, 1], pts[:, 0])
            x = x / HALF
            y = y / HALF
            # spezza dove la linea attraversa la cucitura del cilindro
            cut = np.nonzero(np.abs(np.diff(x)) > w / 2)[0] + 1
            for seg_x, seg_y in zip(np.split(x, cut), np.split(y, cut)):
                if len(seg_x) > 1:
                    d.line(list(zip(seg_x.tolist(), seg_y.tolist())), fill=255, width=2)
    return np.asarray(img) > 0


def warp(lab, passable, rivers, seeds_yx=None, seed=5):
    """Confini meno geometrici: ogni pixel prende l'etichetta di un punto vicino spostato da un campo di rumore liscio
    (domain warping, WARP_AMP pixel a mezza risoluzione, a due scale). Vicino ai fiumi lo spostamento si spegne, cosi' i
    confini che corrono lungo un fiume restano sul fiume."""
    h, w = lab.shape
    rng = np.random.default_rng(seed)

    def field(scale, amp):
        g = rng.standard_normal((h // scale + 3, w // scale + 3)).astype(np.float32)
        up = np.asarray(Image.fromarray(g).resize(((w // scale + 3) * scale, (h // scale + 3) * scale), Image.BICUBIC))
        return amp * up[:h, :w]
    dx = field(120, WARP_AMP * 1.4) + field(48, WARP_AMP) + field(14, WARP_AMP * 0.35)
    dy = field(120, WARP_AMP * 1.4) + field(48, WARP_AMP) + field(14, WARP_AMP * 0.35)
    near = ndimage.distance_transform_edt(~rivers)
    # spegnimento graduale (su 40 px): uno scalino brusco lasciava lungo i fiumi strisce con l'etichetta non spostata
    fade = np.clip(near / 40.0, 0.0, 1.0).astype(np.float32)
    if seeds_yx is not None:
        # niente spostamento attorno ai semi (capitali comprese): il castello resta nella sua regione
        pts = np.ones((h, w), bool)
        pts[seeds_yx[0], seeds_yx[1]] = False
        fade = np.minimum(fade, np.clip((ndimage.distance_transform_edt(pts) - 4.0) / 20.0, 0.0, 1.0))
    fade = (fade * fade * (3 - 2 * fade)).astype(np.float32)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    sx = np.round(xs + dx * fade).astype(np.int64) % w
    sy = np.clip(np.round(ys + dy * fade).astype(np.int64), 0, h - 1)
    out = lab[sy, sx]
    out[~passable] = 0
    bad = passable & (out == 0)
    return nearest_fill(out, out > 0, bad)


def one_piece_per_landmass(full, mask, comp, castles):
    """Una regione non puo' avere due pezzi sulla stessa terraferma o isola (28/11/2026: Svizzera e Fezzan uscivano
    spaccati in due). Su ogni terra tiene il pezzo con la capitale, o il piu' grande; gli altri pezzi vanno alle regioni
    vicine. Pezzi su isole diverse (arcipelaghi) restano."""
    for _ in range(4):
        loose = np.zeros(full.shape, bool)
        for i, s in enumerate(ndimage.find_objects(full), start=1):
            if s is None:
                continue
            m = full[s] == i
            pieces, n = ndimage.label(m)
            if n <= 1:
                continue
            sizes = np.bincount(pieces.ravel())
            land_of = {}
            for k in range(1, n + 1):
                ys, xs = np.nonzero(pieces == k)
                land_of.setdefault(int(comp[s][ys[0], xs[0]]), []).append(k)
            cy, cx = castles.get(i, (-1, -1))
            ck = 0
            if s[0].start <= cy < s[0].stop and s[1].start <= cx < s[1].stop:
                ck = int(pieces[cy - s[0].start, cx - s[1].start])
            for land, ks in land_of.items():
                if len(ks) < 2:
                    continue
                keep = ck if ck in ks else max(ks, key=lambda k: sizes[k])
                for k in ks:
                    if k == keep:
                        continue
                    # pezzo staccato: alla regione vicina piu' vicina (mai di nuovo a questa), in una finestra attorno
                    ys, xs = np.nonzero(pieces == k)
                    y0, y1 = max(0, ys.min() + s[0].start - 60), min(full.shape[0], ys.max() + s[0].start + 61)
                    x0, x1 = max(0, xs.min() + s[1].start - 60), min(full.shape[1], xs.max() + s[1].start + 61)
                    win = full[y0:y1, x0:x1]
                    tgt = np.zeros(win.shape, bool)
                    tgt[ys + s[0].start - y0, xs + s[1].start - x0] = True
                    ok = (win > 0) & (win != i) & mask[y0:y1, x0:x1]
                    if not ok.any():
                        continue
                    idx = ndimage.distance_transform_edt(~ok, return_distances=False, return_indices=True)
                    win[tgt] = win[idx[0][tgt], idx[1][tgt]]
                    full[y0:y1, x0:x1] = win
                    loose[y0, x0] = True
        if not loose.any():
            break
    return full


def downsample_mask(mask, f):
    h, w = mask.shape
    hh, ww = h // f, w // f
    return mask[:hh * f, :ww * f].reshape(hh, f, ww, f).mean(axis=(1, 3)) >= 0.5


def nearest_fill(lab, valid, target):
    if not target.any():
        return lab
    idx = ndimage.distance_transform_edt(~valid, return_distances=False, return_indices=True)
    lab[target] = lab[idx[0][target], idx[1][target]]
    return lab


def main(defs_path, data_dir, geo, out):
    os.makedirs(out, exist_ok=True)
    defs = definizioni.load(defs_path)
    terra = [d for d in defs if d.kind == 'TERRA']
    # con EUROPA si ridisegnano anche le 107 province europee (28/11/2026: «alcune regioni sono davvero molto deformate»)
    grow_defs = terra + ([d for d in defs if d.kind == 'EU'] if EUROPA else [])
    mondo = json.load(open(os.path.join(data_dir, 'mondo.json')))
    regs = {r['id']: r for r in mondo['regions']}
    index_of = {r['id']: r['index'] for r in mondo['regions']}
    next_index = max(r['index'] for r in mondo['regions'] if not r['sea']) + 1
    for d in terra:
        if d.id not in index_of:
            index_of[d.id] = next_index
            next_index += 1
    if next_index >= SEA_FIRST:
        raise SystemExit('troppe regioni di terra')
    old_terra = [d.id for d in terra if d.id in regs]
    old_grow = [d.id for d in grow_defs if d.id in regs]
    lab_old = read_index(os.path.join(data_dir, 'regioni.png'))
    auror_old = read_index(os.path.join(data_dir, 'regioni_auror.png'))
    H, W = lab_old.shape
    mask = np.isin(lab_old, np.array([index_of[r] for r in old_grow], np.uint16))
    print('pixel da ridisegnare', int(mask.sum()))

    # ---- costo a mezza risoluzione
    mh = downsample_mask(mask, HALF)
    h, w = mh.shape
    elev = elevation_grid(geo, w, h, HALF)
    gy, gx = np.gradient(ndimage.gaussian_filter(elev, 1.0))
    cost = 1.0 + SLOPE_COST * np.hypot(gx, gy) + 2.0 * np.clip(elev - 0.35, 0, 1)
    rivers = river_mask(geo, h, w)
    cost = cost + RIVER_COST * rivers
    cost = (cost * np.exp(NOISE_AMP * fractal_noise(h, w))).astype(np.float64)

    # ---- semi
    lab_index = {d.id: index_of[d.id] for d in grow_defs}
    speed = np.ones(next_index + 1, np.float64)
    for d in grow_defs:
        speed[lab_index[d.id]] = d.speed
    sy, sx, sl = [], [], []
    seeds_full = {}
    for d in grow_defs:
        # anche la capitale e' un seme: cosi' la citta' del castello cade nella sua regione
        for la, lo in d.seeds + [d.castle]:
            x, y = P.to_px(la, lo)
            s = snap(mh, y / HALF, x / HALF, maxr=60)
            if s is None:
                print('SEME SENZA POSTO', d.id, la, lo)
                continue
            sy.append(s[0]); sx.append(s[1]); sl.append(lab_index[d.id])
            seeds_full.setdefault(lab_index[d.id], []).append((min(H - 1, s[0] * HALF), (s[1] * HALF) % W))
    if EUROPA:
        # province europee: anche il centro (polo interno) della forma di prima, cosi' restano dove stavano
        objs_old = ndimage.find_objects(lab_old.astype(np.int32))
        for d in grow_defs:
            if d.kind != 'EU':
                continue
            i = index_of[d.id]
            so = objs_old[i - 1] if i - 1 < len(objs_old) else None
            if so is None:
                continue
            mo = lab_old[so] == i
            cl, n = ndimage.label(mo)
            if n > 1:
                mo = cl == (np.bincount(cl.ravel())[1:].argmax() + 1)
            px, py, _ = F3.pole(mo)
            yy, xx = (py + so[0].start) // HALF, (px + so[1].start) // HALF
            if 0 <= yy < h and 0 <= xx < w and mh[yy, xx]:
                sy.append(yy); sx.append(xx); sl.append(lab_index[d.id])
                seeds_full.setdefault(lab_index[d.id], []).append((py + so[0].start, px + so[1].start))
    castles_full = {}
    for d in grow_defs:
        cx, cy = P.to_px(*d.castle)
        castles_full[lab_index[d.id]] = (int(np.clip(cy, 0, H - 1)), int(cx) % W)
    missing = [d.id for d in grow_defs if lab_index[d.id] not in seeds_full]
    if missing:
        raise SystemExit('regioni senza semi validi: %s' % missing)
    seed_args = (np.array(sy, np.int64), np.array(sx, np.int64), np.array(sl, np.int32))
    grown = crescita.grow(mh, cost, *seed_args, speed)
    if EUROPA:
        # le province europee tengono piu' o meno l'estensione di prima: velocita' corretta in qualche giro
        target = np.bincount(np.asarray(Image.fromarray(lab_old.astype(np.int32)).resize((w, h), Image.NEAREST)).ravel(),
                             minlength=next_index + 1).astype(np.float64)
        eu_idx = np.array([index_of[d.id] for d in grow_defs if d.kind == 'EU'])
        for it in range(EU_ROUNDS):
            area = np.bincount(grown.ravel(), minlength=next_index + 1).astype(np.float64)
            ratio = target[eu_idx] / np.maximum(area[eu_idx], 1.0)
            speed[eu_idx] *= np.clip(np.sqrt(ratio), 0.7, 1.45)
            grown = crescita.grow(mh, cost, *seed_args, speed)
            err = np.abs(np.log(np.maximum(area[eu_idx], 1) / np.maximum(target[eu_idx], 1)))
            print('giro %d: scarto medio delle aree europee %.0f%%' % (it + 1, 100 * (np.exp(err.mean()) - 1)))
    grown = nearest_fill(grown, grown > 0, mh & (grown == 0))
    grown = warp(grown, mh, rivers, (seed_args[0], seed_args[1]))
    print('crescita fatta')

    # ---- piena risoluzione
    up = np.repeat(np.repeat(grown, HALF, axis=0), HALF, axis=1)
    full = np.zeros((H, W), np.int32)
    full[:up.shape[0], :up.shape[1]] = up
    full[~mask] = 0
    full = nearest_fill(full, full > 0, mask & (full == 0))

    # isole: in ogni pezzo di terra ridisegnata valgono solo le regioni con un seme li' (se ce ne sono)
    comp, ncomp = ndimage.label(mask)
    seeds_in = {}
    for i, pts in seeds_full.items():
        for (y, x) in pts:
            c = comp[y, x]
            if c == 0:
                win = comp[max(0, y - 6):y + 7, max(0, x - 6):x + 7]
                vals = win[win > 0]
                if vals.size == 0:
                    continue
                c = np.bincount(vals).argmax()
            seeds_in.setdefault(int(c), set()).add(i)
    objs = ndimage.find_objects(comp)
    # pezzi di terra senza nessun seme (isolette): restano alla regione di prima
    unseeded = np.isin(comp, np.array([c for c in range(1, ncomp + 1) if c not in seeds_in], np.int64))
    full[unseeded] = lab_old[unseeded]
    for c, allowed_set in seeds_in.items():
        sl_ = objs[c - 1]
        sub = full[sl_]
        m = comp[sl_] == c
        allowed = np.isin(sub, np.array(sorted(allowed_set)))
        bad = m & ~allowed
        if bad.any() and (m & allowed).any():
            di = ndimage.distance_transform_edt(~(m & allowed), return_distances=False, return_indices=True)
            sub[bad] = sub[di[0][bad], di[1][bad]]
            full[sl_] = sub
    # pezzi staccati senza seme che toccano altra terra ridisegnata: alla regione vicina
    for _ in range(2):
        orphan = np.zeros((H, W), bool)
        objs_l = ndimage.find_objects(full)
        for i, s in enumerate(objs_l, start=1):
            if s is None:
                continue
            m = full[s] == i
            pieces, n = ndimage.label(m)
            if n <= 1:
                continue
            sizes = np.bincount(pieces.ravel())
            sizes[0] = 0
            keep = {int(sizes.argmax())}
            for (py, px) in seeds_full.get(i, []):
                ly, lx = py - s[0].start, px - s[1].start
                if 0 <= ly < m.shape[0] and 0 <= lx < m.shape[1]:
                    win = pieces[max(0, ly - 6):ly + 7, max(0, lx - 6):lx + 7]
                    vals = win[win > 0]
                    if vals.size:
                        keep.add(int(np.bincount(vals).argmax()))
            bad = (pieces > 0) & ~np.isin(pieces, np.array(sorted(keep)))
            o = orphan[s]
            o |= bad
            orphan[s] = o
        grown_o = ndimage.binary_dilation(orphan, iterations=1) & mask & ~orphan
        touched = np.unique(comp[grown_o])
        orphan &= np.isin(comp, touched[touched > 0])
        if not orphan.any():
            break
        full = nearest_fill(full, (full > 0) & ~orphan, orphan)

    full = one_piece_per_landmass(full, mask, comp, castles_full)
    lab = lab_old.copy()
    lab[mask] = full[mask].astype(np.uint16)
    auror = lab.copy()
    diff = auror_old != lab_old          # l'isola di Atlantide e i mari attorno
    auror[diff] = auror_old[diff]
    write_index(os.path.join(out, 'regioni.png'), lab)
    write_index(os.path.join(out, 'regioni_auror.png'), auror)
    np.save(os.path.join(out, 'regioni.npy'), lab)
    np.save(os.path.join(out, 'regioni_auror.npy'), auror)
    print('bitmap scritte')

    # ---- posizioni delle regioni TERRA
    id_of = {v: k for k, v in index_of.items()}
    pairs_bitmap = crescita.adjacency(lab.astype(np.int32))
    terra_ids = {d.id for d in grow_defs}
    old_ports = {l.split('\t')[1] for l in open(os.path.join(data_dir, 'startpos_mondo.txt'), encoding='latin-1')
                 if l.startswith('SetPort::')}
    sea_ids = {r['id'] for r in mondo['regions'] if r['sea']}
    adj = {}
    for a, b in pairs_bitmap:
        if a in id_of and b in id_of:
            adj.setdefault(id_of[a], set()).add(id_of[b])
            adj.setdefault(id_of[b], set()).add(id_of[a])
    objs_lab = ndimage.find_objects(lab.astype(np.int32))
    by_def = {d.id: d for d in grow_defs}
    new_regs = {}
    for d in grow_defs:
        i = index_of[d.id]
        s = objs_lab[i - 1] if i - 1 < len(objs_lab) else None
        if s is None:
            raise SystemExit('REGIONE SENZA PIXEL %s' % d.id)
        m = lab[s] == i
        cl, n = ndimage.label(m)
        mbig = (cl == (np.bincount(cl.ravel())[1:].argmax() + 1)) if n > 1 else m
        ox, oy = s[1].start, s[0].start
        px, py, _ = F3.pole(mbig)
        info = {'id': d.id, 'index': i, 'sea': False, 'origin': [px + ox, py + oy], 'pixels': int(m.sum())}
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
        coast = sorted(x for x in adj.get(d.id, ()) if x in sea_ids)
        if d.kind == 'EU' and d.id not in old_ports:
            coast = []          # le province europee hanno il porto solo se lo avevano (SetPort dell'originale)
        if coast:
            port = F3.port_position(lab, i, [index_of[x] for x in coast], cx, cy, W, H)
            if port:
                info['port'] = port
        # etichetta (etichette.py)
        dist = ndimage.distance_transform_edt(np.pad(mbig, 1))[1:-1, 1:-1]
        ys, xs = np.mgrid[s[0], s[1]]
        dc = np.hypot(xs - cx, ys - cy)
        score = np.minimum(dist, 25.0) * np.clip(dc / 60.0, 0.15, 1.0) + 0.02 * dist
        score[~mbig] = -1
        k = int(np.argmax(score))
        ly, lx = np.unravel_index(k, score.shape)
        info['label'] = [int(lx + ox), int(ly + oy)]
        new_regs[d.id] = info

    # ---- mondo.json
    out_regions = []
    for r in mondo['regions']:
        if r['id'] in new_regs:
            nr = new_regs[r['id']]
            out_regions.append({'id': r['id'], 'index': r['index'], 'sea': False, 'origin': nr['origin'],
                                'label': nr['label'], 'pixels': nr['pixels']})
        else:
            out_regions.append(r)
    pos = max(k for k, r in enumerate(out_regions) if r['id'] in old_terra) + 1
    added = [{'id': d.id, 'index': index_of[d.id], 'sea': False, 'origin': new_regs[d.id]['origin'],
              'label': new_regs[d.id]['label'], 'pixels': new_regs[d.id]['pixels']} for d in terra if d.id not in regs]
    out_regions[pos:pos] = added
    for r in out_regions:   # pixel delle altre regioni: invariati tranne l'Europa che non cambia
        pass
    mondo['regions'] = out_regions
    json.dump(mondo, open(os.path.join(out, 'mondo.json'), 'w'), separators=(',', ':'))

    # ---- startpos
    text = open(os.path.join(data_dir, 'startpos_mondo.txt'), encoding='latin-1').read().replace('\r\n', '\n')
    lines = text.split('\n')
    old_pairs = set()
    for line in lines:
        if line.startswith('SetNeighbours::'):
            a = line.split('\t')
            r0 = a[1].strip()
            for b in a[2:]:
                b = b.strip()
                if b:
                    old_pairs.add(tuple(sorted((r0, b))))
    pairs = {p for p in old_pairs if p[0] not in terra_ids and p[1] not in terra_ids}
    if EUROPA:
        # i confinanti dello startpos originale valgono tutti (ADR-077), con le zone di mare unite al posto delle tolte
        aliases = {}
        mpath = os.path.join(data_dir, 'mari_uniti.cfg')
        if os.path.exists(mpath):
            sec = ''
            for raw in open(mpath, encoding='utf-8'):
                t = raw.strip()
                if t.startswith('['):
                    sec = t
                elif sec == '[uniti]' and '=' in t and not t.startswith(';'):
                    k, v = t.split('=', 1)
                    aliases[k.strip().upper()] = v.strip().strip('"').upper()
        cand = [os.path.join(data_dir, '..', 'campagna', 'EARLY_XL.TXT'), os.path.join(data_dir, 'EARLY_XL.TXT')]
        for a, b in definizioni.original_neighbours(definizioni.startpos_commands([c for c in cand if os.path.exists(c)][0])):
            a, b = aliases.get(a, a), aliases.get(b, b)
            if a != b:
                pairs.add(tuple(sorted((a, b))))
    for a, bs in adj.items():
        if a in terra_ids:
            for b in bs:
                pairs.add(tuple(sorted((a, b))))
    new_ids = [d.id for d in terra if d.id not in regs]
    out_lines = []
    section = ''
    cand = [os.path.join(data_dir, '..', 'campagna', 'EARLY_XL.TXT'), os.path.join(data_dir, 'EARLY_XL.TXT')]
    cand = [c for c in cand if os.path.exists(c)]
    cmds_goods = definizioni.startpos_commands(cand[0]) if cand else None
    goods_ok = {a[0].upper() for n, a in cmds_goods if n == 'DeclareTradegoods'} if cmds_goods else None
    last_terra_decl = max(k for k, l in enumerate(lines) if l.startswith('DeclareLandRegion::') and
                          l.split('"')[1] in terra_ids)
    attr_end = next(k for k, l in enumerate(lines) if l.startswith('// ---- posizioni'))
    for k, line in enumerate(lines):
        if line.startswith('SetNeighbours::'):
            continue
        head = line.split('::')[0] if '::' in line else ''
        rid = line.split('\t')[1].strip().strip('"') if head and '\t' in line else ''
        if head in ('SetCastle', 'SetOrigin', 'SetPort') and rid in terra_ids:
            continue
        if head == 'SetAttributes' and rid in by_def and rid in regs and by_def[rid].kind == 'TERRA':
            d = by_def[rid]
            f = line.split('\t')
            f[2] = '"%s"' % d.en
            f[9] = '"%s Castle"' % d.en
            f[10] = 'COAST' if 'port' in new_regs[rid] else 'INLAND'
            line = '\t'.join(f)
        if head == 'AddTitle' and rid in by_def and rid in regs and by_def[rid].kind == 'TERRA':
            line = re.sub(r'"Governor of [^"]*"', '"Governor of %s"' % by_def[rid].en, line)
        if line.startswith('// ---- confinanti'):
            break
        out_lines.append(line)
        if k == last_terra_decl:
            out_lines.extend('DeclareLandRegion::\t"%s"' % rid for rid in new_ids)
        if k == attr_end - 1:
            pass
    # attributi delle regioni nuove: prima delle posizioni
    blk = ['// ---- regioni nuove del 28/11/2026 (tools/mondo/nuove_regioni.py)']
    for rid in new_ids:
        d = by_def[rid]
        r = new_regs[rid]
        coast = 'COAST' if r.get('port') else 'INLAND'
        view = {'ROCK_DESERT': 'HILLY', 'SAND_DESERT': 'FLAT'}.get(d.terrain, 'PLAINS')
        rebellious = 1 if d.culture == 'PAGAN' else 0
        blk.append('SetAttributes::\t%s\t"%s"\t%d\t%s_CULTURE\t%s\t%s\t-1\t%d\t"%s Castle"\t%s\t%s\tNO_RIVER\tTRUE'
                   % (d.id, d.en, rebellious, d.culture, d.terrain, d.arch, d.income, d.en, coast, view))
    for rid in new_ids:
        d = by_def[rid]
        res = list(dict.fromkeys(d.resources + [g for g in d.goods if g in ('GOLD', 'SILVER', 'IRON', 'COPPER')]))
        goods = [g for g in d.goods if (goods_ok is None or g in goods_ok) and g not in res]
        blk.append('SetRegionRebels::\t%s\t%d' % (d.id, d.rebels))
        blk.append('AddTitle::\t%s\t"Governor of %s"\t+1\t0\t0\t0\t0\t0\t0' % (d.id, d.en))
        if goods:
            blk.append('SetTradableGoods::\t%s\t%s' % (d.id, '\t'.join(goods)))
        if res:
            blk.append('SetResources::\t%s\t%s' % (d.id, '\t'.join(res)))
        blk.append('MakeBuilding::\t%s\t%s' % (d.id, 'Castle3' if d.income >= 600 else 'Castle2'))
        if d.income >= 450:
            blk.append('MakeBuilding::\t%s\tImproved_farmland' % d.id)
        for unit, men in d.garrison:
            blk.append('MakeUnit::\t%s\t%s\t%d\t%s_CULTURE' % (d.id, unit, men, d.culture))
    blk.append('')
    ins = next(k for k, l in enumerate(out_lines) if l.startswith('// ---- posizioni'))
    out_lines[ins:ins] = blk
    # posizioni delle regioni TERRA (in coda a quelle di ogni tipo)
    S = P.STARTPOS_SCALE

    def put_after(prefix, new):
        found = [i for i, l in enumerate(out_lines) if l.startswith(prefix)]
        if not found:   # tutte le righe di quel tipo erano di regioni ridisegnate: in coda alle posizioni
            found = [max(i for i, l in enumerate(out_lines)
                         if l.startswith(('// ---- posizioni', 'SetCastle::', 'SetOrigin::', 'SetPort::')))]
        k = found[-1]
        out_lines[k + 1:k + 1] = new
    put_after('SetCastle::', ['SetCastle::\t%s\t%d\t%d' % (d.id, new_regs[d.id]['castle'][0] * S + S // 2,
                                                          new_regs[d.id]['castle'][1] * S + S // 2) for d in grow_defs])
    put_after('SetOrigin::', ['SetOrigin::\t%s\t%d\t%d' % (d.id, new_regs[d.id]['origin'][0] * S + S // 2,
                                                          new_regs[d.id]['origin'][1] * S + S // 2) for d in grow_defs])
    ports = []
    for d in grow_defs:
        p = new_regs[d.id].get('port')
        if p:
            ports.append('SetPort::\t%s\t%d\t%d\t%d' % (d.id, p[0] * S + S // 2, p[1] * S + S // 2,
                                                         GS.port_direction(lab, p[0], p[1])))
    put_after('SetPort::', ports)
    while out_lines and out_lines[-1] == '':
        out_lines.pop()
    out_lines.append('')
    out_lines.append("// ---- confinanti: contatti della mappa del mondo piu' tutti quelli dello startpos originale")
    nb = {}
    for a, b in sorted(pairs):
        nb.setdefault(a, []).append(b)
        nb.setdefault(b, []).append(a)
    order = [r['id'] for r in out_regions if not r.get('auror')]
    for rid in order:
        if rid in nb:
            out_lines.append('SetNeighbours::\t%s\t%s' % (rid, '\t'.join(sorted(nb[rid]))))
    open(os.path.join(out, 'startpos_mondo.txt'), 'w', encoding='latin-1', newline='\r\n').write('\n'.join(out_lines) + '\n')
    # nomi italiani
    open(os.path.join(out, 'nomi_terra.cfg'), 'w', encoding='utf-8').write(
        '\n'.join('%s="%s"' % (d.id, d.it) for d in terra) + '\n')
    json.dump({rid: new_regs[rid] for rid in new_regs}, open(os.path.join(out, 'posizioni_terra.json'), 'w'), indent=0)
    # anteprima
    preview(lab, out, index_of, terra)
    print('regioni TERRA', len(terra), 'nuove', len(new_ids), 'confinanti', len(pairs))


def preview(lab, out, index_of, terra, s=4):
    i = lab[::s, ::s].astype(np.int32)
    p = np.asarray(Image.open(os.path.join(sys.argv[2], 'plancia.jpg')).resize((i.shape[1], i.shape[0]))).copy()
    e = np.zeros(i.shape, bool)
    e[:, 1:] |= i[:, 1:] != i[:, :-1]
    e[1:, :] |= i[1:, :] != i[:-1, :]
    land = (i > 0) & (i < SEA_FIRST)
    land_n = np.zeros_like(land)
    land_n[:, 1:] |= land[:, :-1]
    p[e & land & land_n] = [170, 20, 20]
    Image.fromarray(p).save(os.path.join(out, 'anteprima.jpg'), quality=88)


if __name__ == '__main__':
    main(*sys.argv[1:5])
