"""Confini vettoriali precalcolati della mappa del mondo (ADR-077): stesso algoritmo di src/map/border_extractor.gd
(spigoli tra pixel di regioni diverse, concatenati per coppia, Douglas-Peucker 0,9 e Chaikin x2), ma in Python: sulla
bitmap a 16 bit da 13.000x5.400 pixel GDScript impiegherebbe troppo.

Formato (little endian): "MQB1" magic u32 0x4D514231, versione u32 = 1, larghezza u32, altezza u32, numero u32, poi per
ogni polilinea: gruppo_a u16, gruppo_b u16, tipo u8, chiusa u8, punti u32, punti x (x, y) float32.
Gruppo = indice della regione (terra 1.., mare SEA_FIRST..); 0 = nessuna regione.

Uso: python3 confini_mondo.py <regioni.npy> <uscita.bin> [sea_first]
"""
import struct
import sys
from collections import defaultdict

import numpy as np
from shapely.geometry import LineString

KIND_LAND_LAND, KIND_COAST, KIND_SEA_SEA, KIND_LAND_NONE, KIND_SEA_NONE = range(5)
MAGIC = 0x4D514231


def class_of(g, sea_first):
    return 0 if g <= 0 else (2 if g >= sea_first else 1)


def kind_of(a, b, sea_first):
    ca, cb = class_of(a, sea_first), class_of(b, sea_first)
    if ca == 0 or cb == 0:
        return KIND_SEA_NONE if max(ca, cb) == 2 else KIND_LAND_NONE
    if ca == 1 and cb == 1:
        return KIND_LAND_LAND
    if ca == 2 and cb == 2:
        return KIND_SEA_SEA
    return KIND_COAST


def edges(lab):
    h, w = lab.shape
    stride = w + 1
    out_key, out_v0, out_v1 = [], [], []
    # verticali: tra (y, x-1) e (y, x), linea a x
    a = lab[:, :-1]
    b = lab[:, 1:]
    ys, xs = np.nonzero(a != b)
    xs = xs + 1
    ga, gb = lab[ys, xs - 1].astype(np.int64), lab[ys, xs].astype(np.int64)
    out_key.append(np.minimum(ga, gb) * 65536 + np.maximum(ga, gb))
    out_v0.append(ys.astype(np.int64) * stride + xs)
    out_v1.append((ys.astype(np.int64) + 1) * stride + xs)
    # orizzontali: tra (y, x) e (y+1, x), linea a y+1
    ys, xs = np.nonzero(lab[:-1, :] != lab[1:, :])
    ga, gb = lab[ys, xs].astype(np.int64), lab[ys + 1, xs].astype(np.int64)
    out_key.append(np.minimum(ga, gb) * 65536 + np.maximum(ga, gb))
    v = (ys.astype(np.int64) + 1) * stride + xs
    out_v0.append(v)
    out_v1.append(v + 1)
    return np.concatenate(out_key), np.concatenate(out_v0), np.concatenate(out_v1), stride


def chains(v0, v1):
    """Polilinee da un insieme di spigoli: prima da estremi e incroci, poi i cicli. Lista di (chiusa, [vertici])."""
    adj = defaultdict(list)
    for e in range(len(v0)):
        adj[v0[e]].append(e)
        adj[v1[e]].append(e)
    used = np.zeros(len(v0), bool)
    res = []

    def other(e, v):
        return v1[e] if v0[e] == v else v0[e]

    def walk(start, e):
        path = [start]
        v = start
        while True:
            used[e] = True
            v = other(e, v)
            path.append(v)
            lst = adj[v]
            if len(lst) != 2:
                break
            nxt = -1
            for c in lst:
                if not used[c]:
                    nxt = c
            if nxt < 0:
                break
            e = nxt
        return path

    verts = sorted(adj)
    for v in verts:
        if len(adj[v]) == 2:
            continue
        while True:
            cand = [c for c in adj[v] if not used[c]]
            if not cand:
                break
            e = min(cand, key=lambda c: other(c, v))
            res.append((False, walk(v, e)))
    for v in verts:
        cand = [c for c in adj[v] if not used[c]]
        if cand:
            e = min(cand, key=lambda c: other(c, v))
            res.append((True, walk(v, e)))
    return res


def chaikin(pts, closed, iterations=2):
    cur = pts
    for _ in range(iterations):
        n = len(cur)
        if n < 3 or (closed and n < 4):
            return cur
        if closed:
            p = cur[:-1]
            q = np.roll(p, -1, axis=0)
            out = np.empty((2 * len(p), 2))
            out[0::2] = p * 0.75 + q * 0.25
            out[1::2] = p * 0.25 + q * 0.75
            cur = np.vstack([out, out[:1]])
        else:
            p = cur[:-1]
            q = cur[1:]
            mid = np.empty((2 * len(p), 2))
            mid[0::2] = p * 0.75 + q * 0.25
            mid[1::2] = p * 0.25 + q * 0.75
            cur = np.vstack([cur[:1], mid, cur[-1:]])
    return cur


def main(src, dst, sea_first=1024):
    lab = np.load(src).astype(np.int64)
    h, w = lab.shape
    key, v0, v1, stride = edges(lab)
    order = np.argsort(key, kind='stable')
    key, v0, v1 = key[order], v0[order], v1[order]
    bounds = np.flatnonzero(np.diff(key)) + 1
    starts = np.concatenate([[0], bounds])
    ends = np.concatenate([bounds, [len(key)]])
    out = []
    for s, e in zip(starts, ends):
        k = int(key[s])
        ga, gb = k >> 16, k & 0xFFFF
        kind = kind_of(ga, gb, sea_first)
        for closed, path in chains(v0[s:e].tolist(), v1[s:e].tolist()):
            p = np.array(path, dtype=np.int64)
            pts = np.column_stack([p % stride, p // stride]).astype(np.float64)
            # isolette minuscole: la costa e' gia' dipinta sulla plancia, la polilinea costerebbe solo tempo di disegno
            if closed and kind in (KIND_COAST, KIND_LAND_NONE, KIND_SEA_NONE) and np.ptp(pts, axis=0).max() < 6:
                continue
            if len(pts) >= 3:
                simple = np.asarray(LineString(pts).simplify(0.9, preserve_topology=False).coords)
                if closed and len(simple) < 4:
                    simple = pts
                pts = simple
            pts = chaikin(pts, closed)
            out.append((ga, gb, kind, closed, pts.astype(np.float32)))
    with open(dst, 'wb') as f:
        f.write(struct.pack('<IIIII', MAGIC, 1, w, h, len(out)))
        for ga, gb, kind, closed, pts in out:
            f.write(struct.pack('<HHBBI', ga, gb, kind, 1 if closed else 0, len(pts)))
            f.write(pts.astype('<f4').tobytes())
    print('polilinee', len(out), 'spigoli', len(key))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], *( [int(sys.argv[3])] if len(sys.argv) > 3 else []))
