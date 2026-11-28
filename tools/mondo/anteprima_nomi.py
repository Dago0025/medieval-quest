"""Anteprima di un riquadro della mappa con confini e nomi (controllo a vista delle regioni ridisegnate).
Uso: python3 anteprima_nomi.py <uscita> <lat_nord> <lon_ovest> <lat_sud> <lon_est> <passo> <file.jpg>"""
import json, sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
import proiezione as P, definizioni
Image.MAX_IMAGE_PIXELS = None
out, n, w, s, e, step, dst = sys.argv[1], *map(float, sys.argv[2:7]), sys.argv[7]
step = int(step)
lab = np.load(os.path.join(out, 'regioni.npy')).astype(np.int32)
m = json.load(open(os.path.join(out, 'mondo.json')))
names = {}
extra = os.path.join(os.path.dirname(out), 'dati', 'province.cfg')
for path in ([extra] if os.path.exists(extra) else []) + [os.path.join(out, 'nomi_terra.cfg')]:
    for line in open(path, encoding='utf-8'):
        line = line.strip()
        if line.startswith('ID_') and '=' in line:
            k, v = line.split('=', 1); names[k] = v.strip('"')
x0, y0 = P.to_px(n, w); x1, y1 = P.to_px(s, e)
x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
sub = lab[y0:y1:step, x0:x1:step]
pl = Image.open(os.path.join(os.path.dirname(out), 'dati', 'plancia.jpg')).crop((x0, y0, x1, y1)).resize((sub.shape[1], sub.shape[0]))
p = np.asarray(pl).copy()
ed = np.zeros(sub.shape, bool); ed[:, 1:] |= sub[:, 1:] != sub[:, :-1]; ed[1:, :] |= sub[1:, :] != sub[:-1, :]
p[ed & (sub > 0) & (sub < 1024)] = [170, 20, 20]
im = Image.fromarray(p); d = ImageDraw.Draw(im)
try:
    f = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 11)
except Exception:
    f = ImageFont.load_default()
for r in m['regions']:
    if r['sea'] or r['id'] not in names or 'label' not in r:
        continue
    lx, ly = r['label']
    if x0 <= lx < x1 and y0 <= ly < y1:
        t = names[r['id']]
        X, Y = (lx - x0) / step, (ly - y0) / step
        tw = d.textlength(t, font=f)
        d.text((X - tw / 2, Y - 6), t, font=f, fill=(20, 20, 60), stroke_width=2, stroke_fill=(245, 235, 210))
im.save(dst, quality=85)
print(im.size)
