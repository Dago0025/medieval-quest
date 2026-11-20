"""Crescita delle regioni dai semi sulla geografia reale (ADR-077).

Ogni regione cresce dai suoi semi come un cristallo: un pixel va alla prima regione che lo raggiunge, il tempo di arrivo
e' il costo del percorso (rilievi piu' lenti) diviso per la velocita' della regione. Le regioni restano connesse (o
formate da piu' pezzi solo se hanno piu' semi). La griglia e' un cilindro: il bordo destro tocca il sinistro (Pacifico).
"""
import heapq

import numpy as np
from numba import njit


@njit(cache=True)
def grow(passable, cost, seed_y, seed_x, seed_label, speed):
    h, w = passable.shape
    label = np.zeros((h, w), dtype=np.int32)
    best = np.full((h, w), np.inf, dtype=np.float64)
    heap = [(0.0, np.int64(0), np.int64(0), np.int64(0))]
    heap.pop()
    for i in range(seed_y.shape[0]):
        y = seed_y[i]
        x = seed_x[i]
        if passable[y, x]:
            best[y, x] = 0.0
            heapq.heappush(heap, (0.0, np.int64(y), np.int64(x), np.int64(seed_label[i])))
    dy = np.array([-1, 1, 0, 0, -1, -1, 1, 1])
    dx = np.array([0, 0, -1, 1, -1, 1, -1, 1])
    dd = np.array([1.0, 1.0, 1.0, 1.0, 1.41421356, 1.41421356, 1.41421356, 1.41421356])
    while len(heap) > 0:
        t, y, x, lab = heapq.heappop(heap)
        if label[y, x] != 0:
            continue
        label[y, x] = lab
        sp = speed[lab]
        for k in range(8):
            ny = y + dy[k]
            if ny < 0 or ny >= h:
                continue
            nx = (x + dx[k]) % w
            if label[ny, nx] != 0 or not passable[ny, nx]:
                continue
            nt = t + dd[k] * 0.5 * (cost[y, x] + cost[ny, nx]) / sp
            if nt < best[ny, nx]:
                best[ny, nx] = nt
                heapq.heappush(heap, (nt, np.int64(ny), np.int64(nx), lab))
    return label


def adjacency(label, wrap=True):
    """Coppie (a, b) con a < b di etichette diverse e non nulle che si toccano (4-vicinanza, cilindro)."""
    pairs = set()
    a = label[:, :-1]
    b = label[:, 1:]
    _collect(pairs, a, b)
    _collect(pairs, label[:-1, :], label[1:, :])
    if wrap:
        _collect(pairs, label[:, -1:], label[:, :1])
    return pairs


def _collect(pairs, a, b):
    m = (a != b) & (a > 0) & (b > 0)
    if not m.any():
        return
    av = a[m]
    bv = b[m]
    lo = np.minimum(av, bv).astype(np.int64)
    hi = np.maximum(av, bv).astype(np.int64)
    keys = np.unique(lo * 100000 + hi)
    for k in keys:
        pairs.add((int(k // 100000), int(k % 100000)))
