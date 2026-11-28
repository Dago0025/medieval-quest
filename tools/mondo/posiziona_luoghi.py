"""Posizioni dei luoghi leggendari sulla plancia del mondo (richiesta di Federico del 26/11/2026).

Per ogni luogo di data/luoghi/luoghi.cfg cerca il pixel piu' vicino al punto reale (lat, lon) che:
  - sta nella sua regione (provincia o zona di mare) ad almeno MARGINE px dal confine;
  - non copre il castello (SetCastle / 16, il castello sta sopra il punto), le pedine alla sua destra, il porto (SetPort),
    il nome della regione (mondo.json "label") ne' le pedine delle zone di mare (ancora "origin");
  - sta ad almeno DIST_LUOGHI px dagli altri luoghi.
  - per i luoghi di terra, sta sulla terra anche nella plancia dipinta (plancia.jpg), a MARGINE_COSTA px dal mare
    dipinto: la costa disegnata non coincide con quella della bitmap delle regioni (Roma finiva in mare, 28/11/2026);
    se nella regione la terra asciutta e' tutta sotto castello e pedine, sulla terra accanto della stessa terraferma.
Nelle regioni troppo piccole (isole) il punto puo' uscire dalla regione, entro FUORI_MAX px da essa.
Scrive data/luoghi/posizioni.cfg ([posizioni] id=Vector2(x, y), pixel della bitmap delle regioni).

Uso: python tools/mondo/posiziona_luoghi.py [cartella del progetto]
"""
import json
import math
import os
import re
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import proiezione as P  # noqa: E402

Image.MAX_IMAGE_PIXELS = None

MARGINE = 10          # distanza minima dal confine della regione
MARGINE_COSTA = 8     # distanza minima dal mare della plancia dipinta (luoghi di terra)
MARGINE_COSTA_MIN = 4 # nelle regioni piccole e coperte dal castello (Roma) basta questa, pur di restare nella regione
DIST_LUOGHI = 60      # distanza minima tra due luoghi
FUORI_MAX = 140       # quanto puo' uscire dalla regione un luogo di una regione troppo piccola
# Ingombri in pixel del mondo (a zoom 1 un pixel del mondo = un punto dello schermo; ADR-064, army_layer.gd):
CASTELLO = (-42, -72, 42, 30)          # rettangolo attorno al punto del castello (sx, alto, dx, basso)
PEDINE_TERRA = (0, -82, 175, 50)       # pedine alla destra del castello, fino a 4 per riga e due righe
PEDINE_MARE = (-95, -82, 95, 44)       # pedine delle flotte attorno all'ancora della zona
FORTEZZA_SCALA = 2.6                   # fortezza degli Auror (FortressArt.MAP_SCALE) piu' grande di un castello
PORTO_RAGGIO = 34
NOME = (-80, -16, 80, 16)              # nome della regione attorno al punto del nome
# Luoghi da cercare a partire dal porto della loro regione invece che dal punto reale: id -> spostamento (dx, dy) dal porto.
# Roma (richiesta di Federico del 28/11/2026): a sud del porto della regione di Roma, non verso la Toscana.
DAL_PORTO = {"roma": (0, 30)}


def leggi_luoghi(path):
    luoghi, cur = {}, None
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        m = re.match(r"^\[([a-z_]+)\]$", line)
        if m:
            cur = m.group(1)
            luoghi[cur] = {}
            continue
        if line.startswith("[") or line.startswith(";"):
            cur = None if line.startswith("[") else cur
            continue
        if cur and "=" in line:
            k, v = line.split("=", 1)
            if k in ("regione", "categoria"):
                luoghi[cur][k] = v.strip().strip('"')
            elif k in ("lat", "lon"):
                luoghi[cur][k] = float(v)
            elif k == "solo_auror":
                luoghi[cur][k] = v.strip() == "true"
    return luoghi


def leggi_startpos(paths):
    castelli, porti = {}, {}
    for p in paths:
        if not os.path.exists(p):
            continue
        for line in open(p, encoding="latin-1"):
            parts = line.split()
            if len(parts) >= 4 and parts[0] == "SetCastle::":
                castelli[parts[1].upper()] = (int(parts[2]) / P.STARTPOS_SCALE, int(parts[3]) / P.STARTPOS_SCALE)
            elif len(parts) >= 4 and parts[0] == "SetPort::":
                porti[parts[1].upper()] = (int(parts[2]) / P.STARTPOS_SCALE, int(parts[3]) / P.STARTPOS_SCALE)
    return castelli, porti


def rett(mask_free, x0, y0, box, ox, oy, scala=1.0):
    """Toglie da `mask_free` (finestra con origine ox, oy) il rettangolo `box` attorno al punto (x0, y0)."""
    l, t, r, b = (v * scala for v in box)
    xa, xb = int(math.floor(x0 + l - ox)), int(math.ceil(x0 + r - ox))
    ya, yb = int(math.floor(y0 + t - oy)), int(math.ceil(y0 + b - oy))
    h, w = mask_free.shape
    mask_free[max(0, ya):max(0, min(h, yb)), max(0, xa):max(0, min(w, xb))] = False


def cerchio(mask_free, x0, y0, raggio, ox, oy):
    h, w = mask_free.shape
    yy, xx = np.ogrid[0:h, 0:w]
    mask_free[(xx + ox - x0) ** 2 + (yy + oy - y0) ** 2 < raggio ** 2] = False


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..")
    mm = os.path.join(root, "data", "mappa_mondo")
    info = json.load(open(os.path.join(mm, "mondo.json")))
    by_id = {r["id"].upper(): r for r in info["regions"]}
    luoghi = leggi_luoghi(os.path.join(root, "data", "luoghi", "luoghi.cfg"))
    castelli, porti = leggi_startpos([os.path.join(mm, "startpos_mondo.txt"), os.path.join(mm, "startpos_atlantide.txt")])
    rg = {}
    for auror in (False, True):
        img = np.array(Image.open(os.path.join(mm, "regioni_auror.png" if auror else "regioni.png")).convert("RGB"))
        rg[auror] = img[..., 0].astype(np.int32) + 256 * img[..., 1].astype(np.int32)
    H, W = rg[False].shape
    pl = {}
    for auror in (False, True):
        img = np.array(Image.open(os.path.join(mm, "plancia_auror.jpg" if auror else "plancia.jpg")).convert("RGB")).astype(np.int16)
        # terra dipinta: beige/verde con il blu ben sotto rosso e verde; mare e filetto di costa hanno blu >= rosso
        pl[auror] = (np.minimum(img[..., 0], img[..., 1]) - img[..., 2]) > 20
    fatti = {}
    out = ["; Posizioni dei luoghi leggendari sulla plancia del mondo (pixel della bitmap delle regioni).",
           "; Generato da tools/mondo/posiziona_luoghi.py: non modificare a mano, rilanciare lo script.", "", "[posizioni]"]
    report = []
    for lid, d in luoghi.items():
        if "regione" not in d:
            continue
        rid = d["regione"].upper()
        r = by_id.get(rid)
        if r is None:
            report.append(f"ERRORE {lid}: regione {rid} assente in mondo.json")
            continue
        idx = rg[bool(d.get("solo_auror"))]
        ox0, oy0 = r["origin"]
        if lid in DAL_PORTO and rid in porti:
            tx, ty = porti[rid][0] + DAL_PORTO[lid][0], porti[rid][1] + DAL_PORTO[lid][1]
        elif "lat" in d:
            tx, ty = P.to_px(d["lat"], d["lon"])
            tx, ty = float(tx), float(ty)
        else:
            tx, ty = float(ox0), float(oy0)
        # finestra attorno alla regione
        ys, xs = np.nonzero(idx == r["index"])
        if xs.size == 0:
            report.append(f"ERRORE {lid}: nessun pixel per {rid}")
            continue
        x_a, x_b = max(0, xs.min() - FUORI_MAX - 200), min(W, xs.max() + FUORI_MAX + 200)
        y_a, y_b = max(0, ys.min() - FUORI_MAX - 200), min(H, ys.max() + FUORI_MAX + 200)
        win = idx[y_a:y_b, x_a:x_b]
        inside = win == r["index"]
        # erosione di MARGINE: pixel della regione lontani dal confine
        core = inside.copy()
        pad = np.pad(inside, MARGINE, constant_values=False)
        for dy in range(-MARGINE, MARGINE + 1, 2):
            for dx in range(-MARGINE, MARGINE + 1, 2):
                if dx * dx + dy * dy <= MARGINE * MARGINE:
                    core &= pad[MARGINE + dy:MARGINE + dy + inside.shape[0], MARGINE + dx:MARGINE + dx + inside.shape[1]]
        land = pl[bool(d.get("solo_auror"))][y_a:y_b, x_a:x_b]
        if not r.get("sea"):
            padl = np.pad(land, MARGINE_COSTA, constant_values=False)
            dry = land.copy()
            for dy in range(-MARGINE_COSTA, MARGINE_COSTA + 1, 2):
                for dx in range(-MARGINE_COSTA, MARGINE_COSTA + 1, 2):
                    if dx * dx + dy * dy <= MARGINE_COSTA * MARGINE_COSTA:
                        dry &= padl[MARGINE_COSTA + dy:MARGINE_COSTA + dy + land.shape[0], MARGINE_COSTA + dx:MARGINE_COSTA + dx + land.shape[1]]
            padl = np.pad(land, MARGINE_COSTA_MIN, constant_values=False)
            dry_min = land.copy()
            for dy in range(-MARGINE_COSTA_MIN, MARGINE_COSTA_MIN + 1):
                for dx in range(-MARGINE_COSTA_MIN, MARGINE_COSTA_MIN + 1):
                    if dx * dx + dy * dy <= MARGINE_COSTA_MIN * MARGINE_COSTA_MIN:
                        dry_min &= padl[MARGINE_COSTA_MIN + dy:MARGINE_COSTA_MIN + dy + land.shape[0], MARGINE_COSTA_MIN + dx:MARGINE_COSTA_MIN + dx + land.shape[1]]
        else:
            dry = np.ones_like(inside)
            dry_min = dry

        def ingombri(scala_ing, pedine_altri=True):
            free = np.ones_like(inside)
            # ingombri di tutte le regioni vicine (anche le confinanti: castelli e nomi sconfinano)
            for oid, o in by_id.items():
                if o.get("auror") and not d.get("solo_auror"):
                    continue
                if oid in castelli and not o.get("sea"):
                    cx, cy = castelli[oid]
                    if x_a - 300 < cx < x_b + 300 and y_a - 300 < cy < y_b + 300:
                        scala = FORTEZZA_SCALA if oid == "ID_ATLANTIS" else 1.0
                        rett(free, cx, cy, CASTELLO, x_a, y_a, scala * scala_ing)
                        if pedine_altri or oid == rid:
                            rett(free, cx, cy, PEDINE_TERRA, x_a, y_a, (1.0 if scala == 1.0 else 1.6) * scala_ing)
                if o.get("sea") or oid not in castelli:
                    ax, ay = o["origin"]
                    if x_a - 300 < ax < x_b + 300 and y_a - 300 < ay < y_b + 300:
                        rett(free, ax, ay, PEDINE_MARE, x_a, y_a, scala_ing)
                if oid in porti:
                    px, py = porti[oid]
                    if x_a - 100 < px < x_b + 100 and y_a - 100 < py < y_b + 100:
                        cerchio(free, px, py, PORTO_RAGGIO * scala_ing, x_a, y_a)
                lx, ly = o.get("label", o["origin"])
                if x_a - 200 < lx < x_b + 200 and y_a - 100 < ly < y_b + 100:
                    rett(free, lx, ly, NOME, x_a, y_a, scala_ing)
            for (fx, fy) in fatti.values():
                if x_a - 100 < fx < x_b + 100 and y_a - 100 < fy < y_b + 100:
                    cerchio(free, fx, fy, DIST_LUOGHI * scala_ing, x_a, y_a)
            return free

        yy, xx = np.mgrid[y_a:y_b, x_a:x_b]
        dist = (xx - tx) ** 2 + (yy - ty) ** 2
        # vicinanza alla regione (dilatazione), per i luoghi delle regioni troppo piccole
        near = inside.copy()
        step = 10
        for _ in range(FUORI_MAX // step):
            p2 = np.pad(near, step, constant_values=False)
            near = near | p2[0:-2 * step, step:-step] | p2[2 * step:, step:-step] | p2[step:-step, 0:-2 * step] | p2[step:-step, 2 * step:]
        free1 = ingombri(1.0)
        free2 = ingombri(0.6)
        free_own = ingombri(0.6, False)   # senza le pedine dei castelli di altre regioni (si vedono solo se ci sono eserciti)
        # terra dipinta della stessa terraferma, raggiungibile dalla terra asciutta della regione entro FUORI_MAX px: per le
        # regioni tutte coperte dal castello (Roma) il luogo va sulla terra accanto, mai su un'altra isola o oltre il mare
        mass = inside & dry
        if mass.any() and not r.get("sea"):
            step = 4
            for _ in range(FUORI_MAX // step):
                p2 = np.pad(mass, step, constant_values=False)
                grown = mass | p2[0:-2 * step, step:-step] | p2[2 * step:, step:-step] | p2[step:-step, 0:-2 * step] | p2[step:-step, 2 * step:]
                grown &= dry
                if (grown == mass).all():
                    break
                mass = grown
        landmass = mass & (win > 0) & (win < info["sea_first"])
        # prima i punti sulla terra dipinta dentro la regione (anche con ingombri molto ridotti), poi le regole di prima
        tiers = [(core & free1 & dry, ""), (inside & free1 & dry, " (vicino al confine)"),
                 (core & free2 & dry, " (ingombri ridotti)"), (inside & free2 & dry, " (vicino al confine, ingombri ridotti)"),
                 (inside & free2 & dry_min, " (nella regione, vicino a costa e confine, ingombri ridotti)"),
                 (inside & free_own & dry_min, " (nella regione, sotto le pedine di un castello vicino)"),
                 (landmass & free2, " (sulla terra accanto alla regione)"),
                 (core & free1, " (costa dipinta)"), (inside & free1, " (costa dipinta, vicino al confine)"),
                 (core & free2, " (costa dipinta, ingombri ridotti)"),
                 (inside & free2, " (costa dipinta, vicino al confine, ingombri ridotti)"),
                 (near & free1 & (win >= info["sea_first"]), " (in mare accanto alla regione: troppo piccola)"),
                 (near & free1 & (win > 0), " (fuori dalla regione: troppo piccola)")]
        if lid in DAL_PORTO and rid in porti:
            # a ridosso del porto anche sotto castello e pedine (il luogo si disegna sotto di loro): basta stare nella
            # regione, sulla terra dipinta e fuori dal molo
            pqx, pqy = porti[rid]
            off_port = (xx - pqx) ** 2 + (yy - pqy) ** 2 > 16 ** 2
            tiers = [((win == r["index"]) & dry_min & off_port & (yy > pqy), " (a sud del porto)")] + tiers
        cand, nota = None, ""
        for c, n in tiers:
            if c.any():
                cand, nota = c, n
                break
        if cand is None:
            cand = np.zeros_like(inside)
        if not cand.any():
            report.append(f"ERRORE {lid}: nessun punto libero")
            continue
        dist = np.where(cand, dist, np.inf)
        k = int(np.argmin(dist))
        py, px = divmod(k, dist.shape[1])
        x, y = px + x_a, py + y_a
        fatti[lid] = (x, y)
        actual = int(idx[y, x])
        actual_id = next((i for i, o in by_id.items() if o["index"] == actual), "?")
        spost = math.hypot(x - tx, y - ty)
        ti = int(idx[int(min(H - 1, max(0, ty))), int(min(W - 1, max(0, tx)))])
        real_id = next((i for i, o in by_id.items() if o["index"] == ti), "?")
        report.append(f"{lid:14s} {rid:20s} -> ({x},{y}) in {actual_id} spostato {spost:.0f}px{nota} [punto reale in {real_id}]")
        out.append(f"{lid}=Vector2({x}, {y})")
    open(os.path.join(root, "data", "luoghi", "posizioni.cfg"), "w", encoding="utf-8").write("\n".join(out) + "\n")
    print("\n".join(report))


if __name__ == "__main__":
    main()
