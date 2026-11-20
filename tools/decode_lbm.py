"""Decodifica IFF PBM (ByteRun1) di LukMap.Lbm / LUKUPMAP.LBM e analizza regioni.
Uso: python3 -I decode_lbm.py <file.lbm> <outdir>
Scrive: index.npy (indici palette HxW), palette.json, preview.png, report su stdout."""
import sys, struct, json, os
import numpy as np
from PIL import Image

def read_pbm(path):
    d = open(path, 'rb').read()
    assert d[:4] == b'FORM' and d[8:12] == b'PBM ', 'non e PBM'
    pos = 12; chunks = {}
    while pos + 8 <= len(d):
        cid = d[pos:pos+4]; ln = struct.unpack('>I', d[pos+4:pos+8])[0]
        chunks[cid] = d[pos+8:pos+8+ln]
        pos += 8 + ln + (ln & 1)
    w, h, x, y, nplanes, mask, comp, pad, trans, xa, ya, pw, ph = struct.unpack('>HHhhBBBBHBBhh', chunks[b'BMHD'])
    pal = np.frombuffer(chunks[b'CMAP'], dtype=np.uint8).reshape(-1, 3)
    body = chunks[b'BODY']
    out = bytearray(); i = 0
    if comp == 1:
        while i < len(body) and len(out) < w*h:
            n = body[i]; i += 1
            if n < 128:
                out += body[i:i+n+1]; i += n+1
            elif n > 128:
                out += bytes([body[i]]) * (257-n); i += 1
    else:
        out = bytearray(body)
    # PBM: righe di w byte (arrotondate al pari). Qui w=2048 e' pari.
    arr = np.frombuffer(bytes(out[:w*h]), dtype=np.uint8).reshape(h, w)
    return dict(w=w, h=h, planes=nplanes, comp=comp, trans=trans, pal=pal, idx=arr, decoded=len(out))

if __name__ == '__main__':
    src, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    m = read_pbm(src)
    print('dimensioni', m['w'], 'x', m['h'], 'piani', m['planes'], 'compressione', m['comp'], 'byte decodificati', m['decoded'], 'attesi', m['w']*m['h'])
    idx = m['idx']; pal = m['pal']
    vals, cnt = np.unique(idx, return_counts=True)
    print('indici distinti usati', len(vals), 'su', len(pal), 'voci di palette')
    np.save(os.path.join(outdir, 'index.npy'), idx)
    json.dump({'palette': pal.tolist(), 'counts': {int(v): int(c) for v, c in zip(vals, cnt)}}, open(os.path.join(outdir, 'palette.json'), 'w'))
    Image.fromarray(idx, 'P').convert('P') if False else None
    im = Image.fromarray(idx, 'P'); im.putpalette(pal.flatten().tolist()); im.save(os.path.join(outdir, 'preview.png'))
