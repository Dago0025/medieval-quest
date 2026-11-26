"""Pedine della mappa rifatte con AI Playground (Edit by Prompt 2) dai riferimenti di
AI-Playground/media/conversione_pedine (coda.json, risultati/PD##_*.png).

Uso:  python tools/prepara_pedine.py <conversione_pedine> <campmap esportata> [--solo PD01,PD02] [--foglio anteprima.png]

Per ogni pedina:
- toglie il fondo grigio (piano stimato dai bordi, riempimento dai bordi: anche l'ombra grigia a terra);
- riporta la figura nella cornice dell'originale a SCALA volte (altezza = altezza originale x SCALA, piede allineato),
  stimando dalla sagoma quanto l'IA ha ingrandito o spostato il pezzo;
- rimette i colori chiave che il gioco ricolora (PieceArt): stendardo rosso puro (v,0,0), fascia della base magenta
  (v,0,v) e orlo ciano (0,v,v), solo nelle zone dove l'originale li aveva (allargate di poco), cosi' il rosso dello
  scudo o di un pennacchio non diventa colore di fazione;
- scrive assets/rifatti/<percorso originale minuscolo>.png e accanto .cfg con i rettangoli (pixel della rifatta) di
  stendardo, base e scudo (.cfg), che PieceArt usa per ricolorare solo li' e per posare lo stemma della fazione.
"""
import argparse, json, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCALA = 2
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'rifatti')
SHIELD_ARMY = (4, 152, 31, 47)       # come PieceArt.SHIELD_ARMY / SHIELD_LEADER (pixel dell'originale)
SHIELD_LEADER = (35, 150, 31, 47)


def keys_of(a):
    """Maschere rosso/magenta/ciano chiave dell'originale (stessa regola di PieceArt.key_of)."""
    rgb = a[..., :3].astype(float) / 255.0
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    hi = rgb.max(-1)
    ok = (a[..., 3] > 0) & (hi >= 0.25)
    off, near = hi * 0.33, hi * 0.7
    red = ok & (r >= near) & (g <= off) & (b <= off)
    mag = ok & (r >= near) & (b >= near) & (g <= off)
    cya = ok & (g >= near) & (b >= near) & (r <= off)
    return red, mag, cya


def key_white_banner(a):
    """Lo stendardo dei pagani a piedi e' bianco nell'originale: come nel riferimento (prep_pedine.py) diventa rosso chiave."""
    a = a.copy()
    rgb = a[..., :3].astype(int)
    ys, xs = np.nonzero((a[..., 3] > 0) & (rgb.min(-1) > 150) & (rgb.max(-1) - rgb.min(-1) < 30))
    sel = ys < 150
    ys, xs = ys[sel], xs[sel]
    order = np.sort(xs)
    x0, x1 = order[len(order) // 20], order[-(len(order) // 20)]
    keep = (xs >= x0 - 1) & (xs <= x1 + 1) & (ys > 20)
    ys, xs = ys[keep], xs[keep]
    a[ys, xs, 0] = (rgb[ys, xs].max(-1) * 0.95).astype(np.uint8)
    a[ys, xs, 1] = 0
    a[ys, xs, 2] = 0
    return a


def plane(img):
    """Fondo grigio come piano per canale, stimato dai bordi."""
    h, w = img.shape[:2]
    m = np.zeros((h, w), bool)
    m[:12], m[-12:], m[:, :12], m[:, -12:] = True, True, True, True
    ys, xs = np.nonzero(m)
    A = np.c_[xs, ys, np.ones_like(xs)].astype(float)
    yy, xx = np.mgrid[0:h, 0:w]
    out = np.zeros((h, w, 3))
    for c in range(3):
        coef, *_ = np.linalg.lstsq(A, img[ys, xs, c].astype(float), rcond=None)
        out[..., c] = coef[0] * xx + coef[1] * yy + coef[2]
    return out


def cut_background(img):
    rgb = img[..., :3].astype(float)
    bg = plane(img)
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    lum, blum = rgb.mean(-1), bg.mean(-1)
    diff = np.abs(rgb - bg).max(-1)
    near = diff < 24
    # ombra a terra (anche grigio-azzurra): solo nella fascia bassa, dove sta la base; piu' in alto il grigio di cotte di
    # maglia e armature somiglia troppo al fondo e il riempimento dai bordi ci entrerebbe
    shadow = (sat < 0.17) & (lum > blum * 0.5) & (lum < blum * 1.12)
    # fascia della base: dall'alto della fascia magenta/ciano (nella parte bassa dell'immagine) in giu'
    r_, g_, b_ = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    keyish = (sat > 0.35) & (((r_ > 1.6 * g_) & (b_ > 1.6 * g_)) | ((g_ > 1.6 * r_) & (b_ > 1.6 * r_)))
    keyish[:int(img.shape[0] * 0.55), :] = False
    cnt = keyish.sum(1)
    krows = np.nonzero(cnt > max(20, 0.3 * cnt.max()))[0]   # righe della fascia (le vesti colorate ne hanno pochi)
    top = (krows.min() - 20) if krows.size else int(img.shape[0] * 0.8)
    # ai lati della base l'ombra sale molto (piano del tavolo in prospettiva); sopra la base invece c'e' la figura
    kcols = np.nonzero(keyish[krows].any(0))[0] if krows.size else np.array([])
    shadow[:max(0, top - 320), :] = False
    if kcols.size:
        shadow[:max(0, top), kcols.min():kcols.max() + 1] = False
    else:
        shadow[:max(0, top), :] = False
    # riempimento con soglia stretta (il grigio delle armature chiare arriva a 15-20 dal fondo e il riempimento ci
    # entrava dai bordi morbidi), poi un orlo di qualche pixel con la soglia larga per non lasciare aloni
    cand = ((diff < 12) & (sat < 0.12)) | shadow
    m = Image.fromarray((cand * 255).astype(np.uint8)).copy()   # copia: floodfill non agisce sulla vista dell'array
    h, w = cand.shape
    for x in range(0, w, 32):
        for y in (0, h - 1):
            if m.getpixel((x, y)) == 255:
                ImageDraw.floodfill(m, (x, y), 128)
    for y in range(0, h, 32):
        for x in (0, w - 1):
            if m.getpixel((x, y)) == 255:
                ImageDraw.floodfill(m, (x, y), 128)
    # sacche di fondo chiuse dentro la sagoma (tra stendardo e asta, tra le gambe, sotto la pancia del cavallo): grigio
    # piatto e vicino al piano del fondo, non connesso ai bordi
    arr = np.array(m)
    strict = (diff < 12) & (sat < 0.08)              # sacche: solo il grigio del fondo vero e proprio, non l'ombra
    ys, xs = np.nonzero((arr[::6, ::6] == 255) & strict[::6, ::6])
    lum_f = lum
    for y, x in zip(ys * 6, xs * 6):
        if m.getpixel((int(x), int(y))) != 255:
            continue
        ImageDraw.floodfill(m, (int(x), int(y)), 77)
        arr = np.array(m)
        comp = arr == 77
        n = int(comp.sum())
        flat = n >= 300 and diff[comp].mean() < 6 and lum_f[comp].std() < 4 and strict[comp].mean() > 0.9
        m.paste(Image.fromarray(np.where(comp, 128 if flat else 0, arr).astype(np.uint8)))
    gone = np.array(m) == 128
    loose = near & (sat < 0.14)
    for _ in range(3):
        grown = np.asarray(Image.fromarray((gone * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
        gone = gone | (grown & loose)
    alpha = Image.fromarray(np.where(gone, 0, 255).astype(np.uint8))
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    return np.dstack([img[..., :3], np.asarray(alpha)])


def bbox(mask):
    ys, xs = np.nonzero(mask)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def rekey(a, region, kind):
    """Rimette il colore chiave puro nei pixel della zona che hanno la tinta giusta."""
    rgb = a[..., :3].astype(float)
    mx, mn = rgb.max(-1), rgb.min(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    d = np.maximum(mx - mn, 1)
    hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    vis = (a[..., 3] > 40) & (mx > 55)
    if kind == 'rosso':
        m = vis & region & (sat > 0.42) & ((hue < 22) | (hue > 335))
        a[m, 0], a[m, 1], a[m, 2] = np.minimum(255, mx[m] * 1.0), 0, 0
    elif kind == 'base':
        mag = vis & region & (sat > 0.35) & (hue > 270) & (hue < 340)
        cya = vis & region & (sat > 0.35) & (hue > 160) & (hue < 215)
        a[mag, 0], a[mag, 1], a[mag, 2] = mx[mag], 0, mx[mag]
        a[cya, 0], a[cya, 1], a[cya, 2] = 0, mx[cya], mx[cya]
        m = mag | cya
    return m


def dilate(mask, n):
    im = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(n * 2 + 1))
    return np.asarray(im) > 0


def rect_of(mask):
    if not mask.any():
        return None
    x0, y0, x1, y1 = bbox(mask)
    return [int(x0), int(y0), int(x1 - x0), int(y1 - y0)]


# misura comune della base (pixel della rifatta) e altezza della cornice per categoria: sulla mappa ogni pedina e' disegnata
# a un'altezza fissa (ArmyLayer.PIECE_HEIGHT, AGENT_PIECE_HEIGHT), quindi a parita' di cornice la base resta uguale per
# tutte. Prima l'altezza seguiva l'originale (agenti da 188 a 260 px) e gli agenti alti o in marcia sembravano piu' piccoli.
TARGET = {'stendardo': (150, 460), 'agente': (148, 268)}


def process(entry, result_path, campmap):
    src_rel = entry['sorgente'][len('campmap/'):] + '.png'
    orig = np.array(Image.open(os.path.join(campmap, src_rel)).convert('RGBA'))
    if 'pagan/army_held_' in src_rel.lower():
        orig = key_white_banner(orig)
    k = entry['scala']
    px, py = entry['pos']
    ai = cut_background(np.array(Image.open(result_path).convert('RGB').convert('RGBA')))
    red, mag, cya = keys_of(orig)
    low = src_rel.lower()
    banner = not low.startswith('pieces/agents/') or 'crusade' in low or 'jihad' in low
    base_w, H = TARGET['stendardo' if banner else 'agente']
    # base nell'immagine dell'IA: la fascia magenta/ciano (misurata con le stesse regole di rekey)
    probe = ai.copy()
    sil = bbox(ai[..., 3] > 128)
    lowband = np.zeros(ai.shape[:2], bool)
    lowband[int(sil[3] - 0.25 * (sil[3] - sil[1])):, :] = True    # la base e' nella fascia bassa (vesti magenta in alto)
    ring = rekey(probe, lowband, 'base') & (ai[..., 3] > 128)
    rows = np.nonzero(ring.any(1))[0]
    ring_low = ring[rows.max() - max(4, (rows.max() - rows.min()) // 2):rows.max() + 1] if rows.size else ring
    cols = np.nonzero(ring_low.any(0))[0]
    if cols.size < 10:                                   # base senza colori: si ripiega sulla sagoma in basso
        ab = bbox(ai[..., 3] > 128)
        cols = np.arange(ab[0], ab[2])
    ax0, ax1 = cols.min(), cols.max() + 1
    abot = bbox(ai[..., 3] > 128)[3]
    r = base_w / float(ax1 - ax0)                        # pixel dell'IA -> pixel della rifatta
    acx = (ax0 + ax1) / 2.0
    # larghezza: simmetrica attorno al centro della base, quanto serve alla sagoma
    sx0, sy0, sx1, sy1 = bbox(ai[..., 3] > 128)
    half = max(acx - sx0, sx1 - acx) * r + 3
    W = int(np.ceil(2 * half))
    P = (W / 2.0, H - 2.0)                               # centro basso della base nella rifatta
    if (abot - sy0) * r > H - 2:
        print('  attenzione: %s esce in alto di %d px' % (entry['id'], (abot - sy0) * r - H + 2))
    big = Image.fromarray(ai).convert('RGBa')
    small = big.resize((max(1, round(1024 * r)), max(1, round(1024 * r))), Image.LANCZOS)
    frame = Image.new('RGBa', (W, H), (0, 0, 0, 0))
    frame.paste(small, (round(P[0] - acx * r), round(P[1] - abot * r)))
    a = np.array(frame.convert('RGBA'))
    a[a[..., 3] < 8] = 0
    # maschera facoltativa <risultato>_protetto.png (bianco = figura davanti allo stendardo, es. drago e cavaliere della
    # pedina di Ankalagon): li' i rossi restano colori dipinti e non diventano rosso chiave (colore della fazione)
    prot = np.zeros((H, W), bool)
    prot_p = os.path.splitext(result_path)[0] + '_protetto.png'
    if os.path.isfile(prot_p):
        pm = Image.open(prot_p).convert('L').resize((max(1, round(1024 * r)), max(1, round(1024 * r))), Image.BILINEAR)
        pf = Image.new('L', (W, H), 0)
        pf.paste(pm, (round(P[0] - acx * r), round(P[1] - abot * r)))
        prot = np.asarray(pf) > 60
    # originale -> IA (sagome: scala dall'altezza, piede allineato) -> rifatta
    # allineamento sulla base (la sagoma dell'IA puo' avere residui ai lati che sposterebbero il centro)
    ox0, oy0, ox1, oy1 = bbox(orig[..., 3] > 0)
    ocols = np.nonzero((mag | cya).any(0))[0]
    if ocols.size and cols.size >= 10:
        s_ai = (ax1 - ax0) / ((ocols.max() + 1 - ocols.min()) * k)
        ocx = (ocols.min() + ocols.max() + 1) / 2.0
    else:
        gx0, gy0, gx1, gy1 = bbox(ai[..., 3] > 128)
        s_ai = (gy1 - gy0) / ((oy1 - oy0) * k)
        ocx = (ox0 + ox1) / 2.0
    tx = acx - s_ai * (px + ocx * k)
    ty = abot - s_ai * (py + oy1 * k)
    so = s_ai * k * r                                    # pixel dell'originale -> pixel della rifatta
    off = ((s_ai * px + tx - acx) * r + P[0], (s_ai * py + ty - abot) * r + P[1])
    oh, ow = orig.shape[:2]

    def up(mask):
        im = Image.fromarray((mask * 255).astype(np.uint8))
        out = im.transform((W, H), Image.AFFINE, (1 / so, 0, -off[0] / so, 0, 1 / so, -off[1] / so), Image.NEAREST)
        return np.asarray(out) > 0
    layout = {'scala': max(1, round(so)), 'margine': 0}
    cover = {}
    # residui grigi fuori dalla sagoma dell'originale accanto allo stendardo e attorno alla base (striscia tra stendardo
    # e asta, ombra a terra): grigio o chiaro poco saturo dove l'originale era trasparente
    empty = np.asarray(Image.fromarray(((orig[..., 3] == 0) * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)))
    empty = up(empty > 0)
    empty = np.asarray(Image.fromarray((empty * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(9))) > 0
    rgb = a[..., :3].astype(float)
    mxx, mnn = rgb.max(-1), rgb.min(-1)
    satx = (mxx - mnn) / np.maximum(mxx, 1)
    grey = (satx < 0.2) & (rgb.mean(-1) > 50)
    zone = np.zeros((H, W), bool)
    if red.any() and banner:
        # accanto allo stendardo, ma non nella sua parte bassa dove spesso c'e' la testa della figura
        bz = dilate(up(red), 20)
        rr = np.nonzero(rekey(a.copy(), dilate(up(red), 16), 'rosso').any(1))[0]   # righe dello stendardo dipinto
        if rr.size:
            bz[int(rr.max() - 0.25 * (rr.max() - rr.min())):, :] = False
        zone |= bz
    if (mag | cya).any():
        btop = np.nonzero(up(mag | cya).any(1))[0]
        if btop.size:
            bandz = np.zeros((H, W), bool)
            bandz[max(0, btop.min() - 40):, :] = True
            # attorno alla base solo l'ombra (grigio medio): un cavallo chiaro che esce dalla sagoma dell'originale resta
            a[bandz & empty & grey & (rgb.mean(-1) < 165)] = 0
    a[zone & empty & grey & ~prot] = 0
    if red.any() and banner:
        # chiazze chiare dipinte dall'IA dentro lo stendardo dell'originale: tornano stendardo (rosso chiave con la loro luce)
        inside = np.asarray(Image.fromarray((up(red) * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))) > 0
        pale = inside & (satx < 0.25) & (mxx > 120) & (a[..., 3] > 40) & ~prot
        a[pale, 0] = (mxx[pale] * 0.85).astype(np.uint8)
        a[pale, 1] = 0
        a[pale, 2] = 0
    if red.any() and banner:   # gli agenti non hanno stendardo: il rosso delle vesti (cardinale, papa) resta com'e'
        m = rekey(a, dilate(up(red), 16) & ~prot, 'rosso')
        layout['stendardo'] = rect_of(m)
        # striscia chiara che l'IA dipinge tra il bordo destro dello stendardo e l'asta: riga per riga, i pixel chiari e
        # poco saturi subito a destra del rosso (fino a 30 px, l'asta e' dorata quindi resta) diventano trasparenti
        ys = np.nonzero(m.any(1))[0]
        if ys.size:
            rgb2 = a[..., :3].astype(float)
            mx2, mn2 = rgb2.max(-1), rgb2.min(-1)
            pale = ((mx2 - mn2) / np.maximum(mx2, 1) < 0.2) & (rgb2.mean(-1) > 100) & (a[..., 3] > 0)
            # la testa della figura (o le vele) arriva spesso al fondo dello stendardo: li' ci si ferma prima
            last = int(ys.max() - 0.25 * (ys.max() - ys.min()))   # vale anche per vele, crociati e guerrieri della jihad
            for y in range(ys.min(), last):
                xr = np.nonzero(m[y])[0]
                if not xr.size:
                    continue
                for x in range(xr.max() + 1, min(W, xr.max() + 41)):
                    if pale[y, x]:
                        a[y, x] = 0
                    elif a[y, x, 3] > 0:
                        break
        cover['stendardo'] = round(m.sum() / max(1, up(red).sum()), 2)
        if 'ships/orthodox' in low and ys.size:
            # galea: l'IA prolunga lo stendardo in un telo grigio fino allo scafo; il telo (grigio chiaro, piatto) va tolto
            xs = np.nonzero(m.any(0))[0]
            y0, y1 = ys.max() + 1, min(H, ys.max() + int(0.45 * (ys.max() - ys.min())))
            reg = np.zeros((H, W), bool)
            reg[y0:y1, max(0, xs.min() - 4):xs.max() + 12] = True
            rgb3 = a[..., :3].astype(float)
            mx3, mn3 = rgb3.max(-1), rgb3.min(-1)
            telo = reg & ((mx3 - mn3) / np.maximum(mx3, 1) < 0.12) & (rgb3.mean(-1) > 130)
            a[telo] = 0
    if (mag | cya).any():
        m = rekey(a, dilate(up(mag | cya), 10), 'base')
        layout['base'] = rect_of(m)
        cover['base'] = round(m.sum() / max(1, up(mag | cya).sum()), 2)
    name = os.path.basename(src_rel).lower()
    if name.startswith('army_held') or name.startswith('army_leader_held'):
        sx, sy, sw, sh = SHIELD_LEADER if 'leader' in name else SHIELD_ARMY
        layout['scudo'] = [round(sx * so + off[0]), round(sy * so + off[1]), round(sw * so), round(sh * so)]
    # granelli staccati dal pezzo (residui dell'ombra o del fondo): via le isole piccole, poi si stringe la cornice
    al = Image.fromarray(((a[..., 3] > 20) * 255).astype(np.uint8)).copy()
    big_part = np.zeros((H, W), bool)
    yy, xx = np.nonzero(np.array(al) == 255)
    for y, x in zip(yy, xx):
        if al.getpixel((int(x), int(y))) != 255:
            continue
        ImageDraw.floodfill(al, (int(x), int(y)), 100)
        comp = np.array(al) == 100
        if comp.sum() >= 60:
            big_part |= comp
        al.paste(Image.fromarray(np.where(comp, 50, np.array(al)).astype(np.uint8)))
    big_part = np.asarray(Image.fromarray((big_part * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(3))) > 0
    a[~big_part] = 0
    xs_used = np.nonzero(a[..., 3].any(0))[0]
    if xs_used.size:
        cut = max(0, min(xs_used.min(), W - 1 - xs_used.max()) - 3)   # simmetrico: il centro della base resta al centro
        if cut > 0:
            a = a[:, cut:W - cut].copy()
            for key in ('stendardo', 'base', 'scudo'):
                if layout.get(key):
                    layout[key][0] -= cut
    layout['_copertura'] = cover   # chiave rimessa / chiave dell'originale: sotto 0,5 la base ha perso i colori
    return a, layout


def write_layout(path, layout):
    """Rettangoli della pedina rifatta in un .cfg (ConfigFile di Godot; i .cfg sono gia' nel filtro di esportazione)."""
    lines = ['; pedina rifatta (tools/prepara_pedine.py): rettangoli [x, y, larghezza, altezza] in pixel dell immagine', '[pedina]']
    for key in ('scala', 'margine', 'stendardo', 'base', 'scudo'):
        v = layout.get(key)
        if v is None:
            continue
        lines.append('%s=%s' % (key, ('[%s]' % ', '.join(str(int(x)) for x in v)) if isinstance(v, list) else int(v)))
    open(path, 'w', newline='\n').write('\n'.join(lines) + '\n')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('conv')
    ap.add_argument('campmap')
    ap.add_argument('--solo', default='')
    ap.add_argument('--foglio', default='')
    args = ap.parse_args()
    queue = json.load(open(os.path.join(args.conv, '_strumenti', 'coda.json'), encoding='utf-8'))
    only = set(x for x in args.solo.split(',') if x)
    done = []
    for e in queue:
        if e['tipo'] != 'pedina' or (only and e['id'] not in only):
            continue
        res = os.path.join(args.conv, 'risultati', os.path.basename(e['file']))
        if not os.path.isfile(res):
            continue
        a, layout = process(e, res, args.campmap)
        # `destinazione`: pedina nuova disegnata sulla sagoma di un'altra (le asiatiche del Dharma sulle pagane, 22/11/2026)
        rel = os.path.splitext(e.get('destinazione', e['sorgente']))[0].lower() + '.png'   # come AssetLibrary.remade_path: senza .bif
        dst = os.path.join(OUT, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.fromarray(a).save(dst)
        write_layout(dst[:-4] + '.cfg', layout)
        done.append((e['id'], a))
        print(e['id'], os.path.basename(rel), a.shape[1], 'x', a.shape[0], layout['_copertura'])
    if args.foglio and done:
        cw = max(x[1].shape[1] for x in done) + 10
        ch = max(x[1].shape[0] for x in done) + 10
        cols = min(len(done), 10)
        sheet = Image.new('RGBA', (cols * cw, ((len(done) + cols - 1) // cols) * ch), (40, 70, 200, 255))
        for i, (_, a) in enumerate(done):
            im = Image.fromarray(a)
            sheet.alpha_composite(im, ((i % cols) * cw + 5, (i // cols) * ch + ch - 5 - im.height))
        sheet.save(args.foglio)


if __name__ == '__main__':
    main()
