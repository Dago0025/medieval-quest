"""Fase 2: l'Europa ricalcata dalla bitmap originale (LukMap) deformata sulla geografia reale.

Corrispondenze: baricentro di ogni regione europea nella LukMap <-> baricentro della stessa regione cresciuta dai semi
(fase 1). Una thin-plate spline levigata porta ogni pixel del mondo nelle coordinate della LukMap; dove la LukMap dice
terra/mare come la costa reale si prende la sua etichetta, altrimenti la regione dello stesso tipo piu' vicina.
Fuori dal riquadro della LukMap restano le etichette della fase 1.

Uso: python3 fase2_europa.py <regioni_mondo.txt> <EARLY_XL.TXT> <index.npy LukMap> <cartella out> [smoothing]
"""
import json
import os
import sys

import numpy as np
from scipy import ndimage
from scipy.interpolate import RBFInterpolator

import crescita
import definizioni
import fase1_regioni as F1


def run(defs_path, startpos_path, lukmap_path, out, smoothing=2.0):
    defs = definizioni.load(defs_path)
    cmds = definizioni.startpos_commands(startpos_path)
    orig_pairs = definizioni.original_neighbours(cmds)
    land_order = [a[0].upper() for n, a in cmds if n == 'DeclareLandRegion']
    sea_order = [a[0].upper() for n, a in cmds if n == 'DeclareSeaRegion']
    idx = np.load(lukmap_path)
    lh, lw = idx.shape
    # etichette originali per id
    orig_label = np.zeros(idx.shape, np.int32)
    index_of = json.load(open(os.path.join(out, 'indici_fase1.json')))
    for k, rid in enumerate(land_order):
        orig_label[((idx >> 1) == k + 1) & (idx < 216)] = index_of[rid]
    for k, rid in enumerate(sea_order):
        orig_label[idx == 216 + k] = index_of[rid]
    orig_is_sea = idx >= 216
    lab1 = np.load(os.path.join(out, 'etichette_mezza.npy'))
    h, w = lab1.shape
    land = F1.downsample_mask(np.load(os.path.join(out, 'terra.npy')).astype(bool), F1.HALF)

    old_sea_idx = [index_of[r] for r in sea_order]
    # corrispondenze
    src, dst = [], []
    ys, xs = np.mgrid[0:h, 0:w]
    for rid in land_order + sea_order:
        i = index_of[rid]
        m1 = lab1 == i
        m0 = orig_label == i
        if not m1.any() or not m0.any():
            continue
        # baricentro nel mondo (attenzione al cilindro: l'Europa e' lontana dalla cucitura)
        wy, wx = ys[m1].mean(), xs[m1].mean()
        oy, ox = np.nonzero(m0)
        src.append((wx, wy))
        dst.append((ox.mean() / 1.0, oy.mean() / 1.0))
    src = np.array(src)
    dst = np.array(dst)
    # punti d'angolo per tenere ferma la deformazione lontano dall'Europa: estrapolazione affine
    rbf = RBFInterpolator(src, dst, kernel='thin_plate_spline', smoothing=float(smoothing), degree=1)
    # zona di lavoro: riquadro attorno alle corrispondenze
    x0, x1 = int(src[:, 0].min() - 400), int(src[:, 0].max() + 400)
    y0, y1 = int(max(0, src[:, 1].min() - 400)), int(min(h, src[:, 1].max() + 400))
    gy, gx = np.mgrid[y0:y1, x0:x1]
    pts = np.column_stack([gx.ravel() + 0.5, gy.ravel() + 0.5])
    mapped = np.empty_like(pts)
    for s in range(0, len(pts), 400000):
        mapped[s:s + 400000] = rbf(pts[s:s + 400000])
    mx = mapped[:, 0].reshape(gx.shape)
    my = mapped[:, 1].reshape(gx.shape)
    inside = (mx >= 0) & (mx < lw) & (my >= 0) & (my < lh)
    mxi = np.clip(mx.astype(np.int64), 0, lw - 1)
    myi = np.clip(my.astype(np.int64), 0, lh - 1)
    warped = np.where(inside, orig_label[myi, mxi], 0)
    warped_sea = np.where(inside, orig_is_sea[myi, mxi], False)
    win_land = land[y0:y1, x0:x1]
    # pixel validi: stesso tipo (terra/mare) tra LukMap e realta'
    ok = (warped > 0) & (warped_sea != win_land)
    # dentro il riquadro della LukMap: terra senza etichetta valida -> regione di terra deformata piu' vicina
    domain = inside & (orig_label[myi, mxi] > 0)
    domain = ndimage.binary_closing(domain, iterations=3)
    # Russia settentrionale: il bordo alto della LukMap tirerebbe Moscovia e Novgorod fino al Mar Bianco; lassu' decidono i semi
    import proiezione as P
    wlat, wlon = P.to_latlon((gx + 0.5) * F1.HALF, (gy + 0.5) * F1.HALF)
    domain &= ~((wlat > 60.5) & (wlon > 31.0) & (wlon < 70.0))
    res = lab1[y0:y1, x0:x1].copy()
    for want_land in (True,):
        valid = ok & (win_land == want_land)
        if not valid.any():
            continue
        di = ndimage.distance_transform_edt(~valid, return_distances=False, return_indices=True)
        near = warped[di[0], di[1]]
        target = domain & (win_land == want_land)
        if not want_land:
            # acque: solo dove la fase 1 ha gia' un mare europeo (Mar Rosso, Caspio, Golfo Persico restano nuovi)
            old_sea = np.isin(lab1[y0:y1, x0:x1], np.array(old_sea_idx))
            target &= old_sea
        res[target] = near[target]
    # isole europee con un seme: tutta l'isola alla regione del seme
    comp, ncomp = ndimage.label(win_land)
    sizes = ndimage.sum(np.ones_like(comp), comp, index=np.arange(ncomp + 1))
    mainland = set(np.argsort(sizes)[-3:].tolist())  # Eurasia+Africa, Gran Bretagna, ...
    seed_comp = {}
    import proiezione as P
    for d in defs:
        if d.is_sea or d.is_new:
            continue
        for la, lo in d.seeds:
            x, y = P.to_px(la, lo)
            cx, cy = int(x / F1.HALF) - x0, int(y / F1.HALF) - y0
            if 0 <= cy < comp.shape[0] and 0 <= cx < comp.shape[1] and comp[cy, cx] > 0:
                c = comp[cy, cx]
                if sizes[c] < 30000:
                    seed_comp.setdefault(c, set()).add(index_of[d.id])
    for c, labs in seed_comp.items():
        if len(labs) == 1:
            res[comp == c] = next(iter(labs))
    label = lab1.copy()
    label[y0:y1, x0:x1] = res
    np.save(os.path.join(out, 'etichette_mezza_f2.npy'), label)
    id_of = {v: k for k, v in index_of.items()}
    pairs = crescita.adjacency(label)
    old = set(land_order + sea_order)
    named = {tuple(sorted((id_of[a], id_of[b]))) for a, b in pairs}
    eu = {p for p in named if p[0] in old and p[1] in old}
    missing = sorted(orig_pairs - eu)
    extra = sorted(eu - orig_pairs)
    rep = ['smoothing %s: originali %d, trovati %d, mancanti %d, in piu\' %d' % (smoothing, len(orig_pairs), len(eu), len(missing), len(extra)),
           'MANCANTI:'] + ['  %s - %s' % p for p in missing] + ['IN PIU\':'] + ['  %s - %s' % p for p in extra]
    open(os.path.join(out, 'confinanti_fase2.txt'), 'w').write('\n'.join(rep))
    print(rep[0])
    F1.preview(label, defs, index_of, land, out)
    os.replace(os.path.join(out, 'anteprima_fase1.png'), os.path.join(out, 'anteprima_fase2.png'))
    np.save(os.path.join(out, 'warp_src.npy'), src)
    np.save(os.path.join(out, 'warp_dst.npy'), dst)


if __name__ == '__main__':
    run(*sys.argv[1:5], *(sys.argv[5:6] or []))
