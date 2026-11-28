"""Punto dei nomi dei mari (28/11/2026, segnalazione di Federico: da lontano i nomi dei mari coprivano le terre, soprattutto
nel Mediterraneo dopo l'unione delle zone). Per ogni zona di mare sceglie il punto dove la scritta, centrata, ha piu' acqua
a destra e a sinistra (sulla riga e 24 pixel sopra e sotto), dentro la zona; lo scrive come "label" in mondo.json.
NameLayer poi riduce il corpo finche' la scritta sta sull'acqua.
Uso: python3 etichette_mari.py <regioni.npy> <mondo.json>"""
import json
import sys

import numpy as np


def runs(water):
    """Per ogni pixel d'acqua: pixel d'acqua contigui a sinistra e a destra sulla stessa riga."""
    h, w = water.shape
    left = np.zeros((h, w), np.int32)
    right = np.zeros((h, w), np.int32)
    acc = np.zeros(h, np.int32)
    for x in range(w):
        acc = np.where(water[:, x], acc + 1, 0)
        left[:, x] = acc
    acc[:] = 0
    for x in range(w - 1, -1, -1):
        acc = np.where(water[:, x], acc + 1, 0)
        right[:, x] = acc
    return left, right


def main(npy, mondo_path):
    lab = np.load(npy)
    m = json.load(open(mondo_path))
    sea_first = m.get('sea_first', 1024)
    s = 2   # mezza risoluzione basta
    sub = lab[::s, ::s]
    water = sub >= sea_first
    left, right = runs(water)
    span = np.minimum(left, right)
    off = 12   # 24 px pieni
    up = np.roll(span, off, axis=0)
    dn = np.roll(span, -off, axis=0)
    # oltre 240 px d'acqua per parte lo spazio basta: da li' conta stare vicino al centro della zona
    score = np.minimum(np.minimum(span, np.minimum(up, dn)), 120).astype(np.float32)
    taken = []   # punti gia' scelti: due nomi di mari non si sovrappongono (zone grandi prima)
    seas = sorted((r for r in m['regions'] if r['sea']), key=lambda r: -r.get('pixels', 0))
    for r in seas:
        mask = sub == r['index']
        if not mask.any():
            continue
        sc = np.where(mask, score, -1)
        # preferenza leggera per il centro della zona (origine) a parita' di spazio
        oy, ox = r['origin'][1] / s, r['origin'][0] / s
        ys, xs = np.nonzero(mask)
        best = sc[ys, xs] - 0.3 * np.hypot(ys - oy, xs - ox)
        for (ty, tx) in taken:
            best = best - 1e6 * np.clip(1.0 - np.hypot(ys - ty, xs - tx) / 90.0, 0.0, 1.0)
        k = int(np.argmax(best))
        taken.append((ys[k], xs[k]))
        r['label'] = [int(xs[k] * s), int(ys[k] * s)]
    json.dump(m, open(mondo_path, 'w'))
    print('etichette dei mari', sum(1 for r in m['regions'] if r['sea'] and 'label' in r))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
