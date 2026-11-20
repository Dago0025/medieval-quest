"""Punto dei nomi delle regioni (NameLayer, ADR-077): dentro la regione, lontano dai bordi e dal castello (dove si
ammassano castello e pedine). Aggiunge "label" a ogni regione di terra di out/finale/mondo.json.
Uso: python3 etichette.py <cartella out>"""
import json
import os
import sys

import numpy as np
from scipy import ndimage


def main(out):
    fin = os.path.join(out, 'finale')
    mondo = json.load(open(os.path.join(fin, 'mondo.json')))
    lab = np.load(os.path.join(fin, 'regioni_auror.npy'))   # contiene anche l'isola
    objs = ndimage.find_objects(lab.astype(np.int32))
    for r in mondo['regions']:
        if r['sea'] or 'castle' not in r:
            continue
        sl = objs[r['index'] - 1]
        m = lab[sl] == r['index']
        pieces, n = ndimage.label(m)
        if n > 1:
            m = pieces == (np.bincount(pieces.ravel())[1:].argmax() + 1)
        d = ndimage.distance_transform_edt(np.pad(m, 1))[1:-1, 1:-1]
        ys, xs = np.mgrid[sl[0], sl[1]]
        cx, cy = r['castle']
        dc = np.hypot(xs - cx, ys - cy)
        # distanza utile dal castello: fino a 60 px conta, oltre e' indifferente
        score = np.minimum(d, 25.0) * np.clip(dc / 60.0, 0.15, 1.0) + 0.02 * d
        score[~m] = -1
        k = int(np.argmax(score))
        py, px = np.unravel_index(k, score.shape)
        r['label'] = [int(px + sl[1].start), int(py + sl[0].start)]
    json.dump(mondo, open(os.path.join(fin, 'mondo.json'), 'w'), indent=1)
    print('etichette', sum(1 for r in mondo['regions'] if 'label' in r))


if __name__ == '__main__':
    main(sys.argv[1])
