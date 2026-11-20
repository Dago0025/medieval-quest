"""Proiezione della mappa del mondo di Medieval Quest (ADR-077).

Miller cilindrica, longitudine da LON_LEFT a LON_LEFT + 360 (centrata sull'Europa), latitudine da LAT_TOP a LAT_BOTTOM.
Coordinate: pixel della bitmap delle regioni (x a destra, y in basso). Lo startpos usa pixel x 16.
"""
import math
import numpy as np

LON_LEFT = -170.0
LAT_TOP = 72.0
LAT_BOTTOM = -55.0
SCALE = 36.0            # pixel per grado all'equatore
STARTPOS_SCALE = 16


def miller_y(lat_deg):
    phi = np.radians(lat_deg)
    return np.degrees(1.25 * np.log(np.tan(math.pi / 4 + 0.4 * phi)))


def miller_lat(y_deg):
    return np.degrees(2.5 * np.arctan(np.exp(0.8 * np.radians(y_deg))) - 0.625 * math.pi)


Y_TOP = float(miller_y(LAT_TOP))
Y_BOTTOM = float(miller_y(LAT_BOTTOM))
WIDTH = int(round(360.0 * SCALE))
HEIGHT = int(round((Y_TOP - Y_BOTTOM) * SCALE))


def wrap_lon(lon):
    """Longitudine nell'intervallo [LON_LEFT, LON_LEFT + 360)."""
    return (np.asarray(lon, dtype=np.float64) - LON_LEFT) % 360.0 + LON_LEFT


def to_px(lat, lon, wrap=True):
    lon = wrap_lon(lon) if wrap else np.asarray(lon, dtype=np.float64)
    x = (lon - LON_LEFT) * SCALE
    y = (Y_TOP - miller_y(np.asarray(lat, dtype=np.float64))) * SCALE
    return x, y


def to_latlon(x, y):
    lon = np.asarray(x, dtype=np.float64) / SCALE + LON_LEFT
    lat = miller_lat(Y_TOP - np.asarray(y, dtype=np.float64) / SCALE)
    return lat, lon


if __name__ == '__main__':
    print('dimensioni', WIDTH, HEIGHT, 'y_top', Y_TOP, 'y_bottom', Y_BOTTOM)
    for name, (la, lo) in {'Roma': (41.9, 12.5), 'Londra': (51.5, -0.1), 'Pechino': (39.9, 116.4)}.items():
        print(name, to_px(la, lo))
