"""Maschere della mappa del mondo a piena risoluzione: terra, laghi, fiumi (Natural Earth 10m).

Uso: python3 maschere.py <cartella geo> <cartella uscita>
Scrive terra.npy (uint8 0/1), laghi.npy (uint8: 0 niente, 1 lago grande, 2 lago piccolo), fiumi.png (spessore in base alla scala).
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

import proiezione as P


def polygons(geojson_path):
    data = json.load(open(geojson_path, encoding='utf-8'))
    for feat in data['features']:
        geom = feat['geometry']
        if geom is None:
            continue
        polys = geom['coordinates'] if geom['type'] == 'MultiPolygon' else [geom['coordinates']]
        for poly in polys:
            yield feat['properties'], poly


def lines(geojson_path):
    data = json.load(open(geojson_path, encoding='utf-8'))
    for feat in data['features']:
        geom = feat['geometry']
        if geom is None:
            continue
        ls = geom['coordinates'] if geom['type'] == 'MultiLineString' else [geom['coordinates']]
        for line in ls:
            yield feat['properties'], line


# Isole troppo piccole per giocarci: ingrandite attorno a un centro (generalizzazione cartografica, ADR-077).
# (lat min, lat max, lon min, lon max, lat centro, lon centro, fattore)
ENLARGE = [
    (35.7, 36.2, 14.0, 14.7, 35.92, 14.38, 3.2),   # Malta e Gozo
    (35.8, 36.5, 27.6, 28.3, 36.17, 27.95, 1.7),   # Rodi
]


def enlarge(a):
    lat = a[:, 1]
    lon = a[:, 0]
    for la0, la1, lo0, lo1, cla, clo, f in ENLARGE:
        if lat.min() >= la0 and lat.max() <= la1 and lon.min() >= lo0 and lon.max() <= lo1:
            a = a.copy()
            a[:, 1] = cla + (lat - cla) * f
            a[:, 0] = clo + (lon - clo) * f
            return a
    return a


def ring_px(ring):
    a = enlarge(np.asarray(ring, dtype=np.float64))
    lat = np.clip(a[:, 1], P.LAT_BOTTOM - 5, P.LAT_TOP + 5)
    x, y = P.to_px(lat, a[:, 0], wrap=False)
    return x, y


def draw_ring(draw, x, y, fill):
    """Disegna un anello anche oltre la cucitura del Pacifico (copie spostate di +-WIDTH)."""
    for off in (0.0, P.WIDTH, -P.WIDTH):
        xs = x + off
        if xs.max() < 0 or xs.min() >= P.WIDTH:
            continue
        draw.polygon(list(zip(xs.tolist(), y.tolist())), fill=fill)


def rasterize(geojson_path, filter_fn=None, value=1):
    img = Image.new('L', (P.WIDTH, P.HEIGHT), 0)
    draw = ImageDraw.Draw(img)
    for props, poly in polygons(geojson_path):
        if filter_fn is not None and not filter_fn(props):
            continue
        x, y = ring_px(poly[0])
        draw_ring(draw, x, y, value)
        for hole in poly[1:]:
            hx, hy = ring_px(hole)
            draw_ring(draw, hx, hy, 0)
    return np.asarray(img, dtype=np.uint8)


def main(geo, out):
    os.makedirs(out, exist_ok=True)
    land = rasterize(os.path.join(geo, 'ne_10m_land.geojson'))
    lakes = rasterize(os.path.join(geo, 'ne_10m_lakes.geojson'))
    np.save(os.path.join(out, 'terra.npy'), land)
    np.save(os.path.join(out, 'laghi.npy'), lakes)
    print('terra', land.mean(), 'laghi', lakes.mean())
    # fiumi: polilinee con spessore dalla classe di scala (scalerank piu' basso = fiume piu' grande)
    img = Image.new('L', (P.WIDTH, P.HEIGHT), 0)
    draw = ImageDraw.Draw(img)
    for props, line in lines(os.path.join(geo, 'ne_10m_rivers_lake_centerlines.geojson')):
        rank = int(props.get("scalerank", 10) or 10)
        if rank > 7:
            continue
        width = max(1, int(round(3.2 - rank * 0.35)))
        x, y = ring_px(line)
        for off in (0.0, P.WIDTH, -P.WIDTH):
            xs = x + off
            if xs.max() < 0 or xs.min() >= P.WIDTH:
                continue
            draw.line(list(zip(xs.tolist(), y.tolist())), fill=int(min(255, 60 + (8 - rank) * 28)), width=width)
    img.save(os.path.join(out, 'fiumi.png'))
    small = Image.fromarray(land * 255).resize((P.WIDTH // 8, P.HEIGHT // 8))
    small.save(os.path.join(out, 'terra_anteprima.png'))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
