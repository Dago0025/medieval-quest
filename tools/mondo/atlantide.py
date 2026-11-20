"""Isola di Atlantide al centro dell'Atlantico (ADR-078): esiste solo nella modalita' Auror.

Forma procedurale nelle coordinate della bitmap: un'isola irregolare con cinque territori, Atlantide al centro (con
gli anelli d'acqua del mito di Platone attorno alla citta') e quattro territori attorno, dai re gemelli del Crizia.
"""
import math

import numpy as np

import proiezione as P

CENTER_LATLON = (35.0, -40.0)
SCALE = 1.3                       # ingrandimento lineare chiesto da Federico (2026-11-16: «almeno il 30%»)
RX, RY = 150.0 * SCALE, 112.0 * SCALE   # semiassi in pixel
CORE_R = 46.0 * SCALE             # raggio del territorio centrale
RINGS = tuple(r * SCALE for r in (13.0, 23.0, 33.0))   # anelli d'acqua attorno alla citta' (raggi in pixel)
RING_W = 2.2 * SCALE
HALF_BOX = (int(300 * SCALE), int(230 * SCALE))         # mezza finestra di lavoro attorno al centro (x, y)

# territori: id, nome it, nome en, angolo centrale del settore (gradi, 0 = est, senso orario sullo schermo)
TERRITORIES = [
    ('ID_ATLANTIS', 'Atlantide', 'Atlantis', None),
    ('ID_GADEIRA', 'Gadira', 'Gadeira', 315.0),      # nord-est: Gadiro, gemello di Atlante
    ('ID_AMPHERIA', 'Amferia', 'Ampheria', 45.0),    # sud-est
    ('ID_MNESEIA', 'Mnesea', 'Mneseia', 135.0),      # sud-ovest
    ('ID_DIAPREPIA', 'Diaprepia', 'Diaprepia', 225.0),  # nord-ovest
]


def center_px():
    x, y = P.to_px(*CENTER_LATLON)
    return float(x), float(y)


def _radius(theta):
    return (1.0 + 0.16 * np.sin(3 * theta + 1.1) + 0.09 * np.sin(5 * theta + 2.3)
            + 0.05 * np.sin(9 * theta + 0.4) + 0.025 * np.sin(17 * theta + 1.7))


def polar(X, Y):
    cx, cy = center_px()
    dx = (X - cx) / RX
    dy = (Y - cy) / RY
    return np.hypot(dx, dy), np.arctan2(dy, dx), np.hypot(X - cx, Y - cy)


def land(X, Y):
    rho, theta, _ = polar(X, Y)
    return rho <= _radius(theta)


def rings(X, Y):
    """Anelli d'acqua (canali) del territorio centrale: acqua dipinta, regione Atlantide."""
    _, _, d = polar(X, Y)
    m = np.zeros(np.shape(X), bool)
    for r in RINGS:
        m |= np.abs(d - r) <= RING_W / 2
    return m


def territory(X, Y):
    """Indice del territorio (0..4, -1 fuori dall'isola)."""
    rho, theta, d = polar(X, Y)
    inside = rho <= _radius(theta)
    deg = (np.degrees(theta)) % 360.0
    # confini dei settori leggermente ondulati
    wobble = 7.0 * np.sin(d / (23.0 * SCALE))
    sector = (((deg + wobble) % 360.0) // 90.0).astype(np.int64)     # 0: 0-90 (sud-est), 1: 90-180 ...
    # settore 0 (0-90 gradi, y in basso) = sud-est -> AMPHERIA (2); 1 = sud-ovest -> MNESEIA (3);
    # 2 = nord-ovest -> DIAPREPIA (4); 3 = nord-est -> GADEIRA (1)
    lut = np.array([2, 3, 4, 1])
    t = lut[sector]
    t = np.where(d <= CORE_R * (1 + 0.06 * np.sin(5 * theta)), 0, t)
    return np.where(inside, t, -1)


def relief(X, Y):
    """Rilievo aggiunto (0..1): monte sacro al centro, catena che corre lungo l'isola."""
    rho, theta, d = polar(X, Y)
    inside = rho <= _radius(theta)
    peak = 0.38 * np.exp(-(d / (8.0 * SCALE)) ** 2)
    k = SCALE
    n = (np.sin(X / (14.1 * k) + 2.0 * np.sin(Y / (31.7 * k))) * np.sin(Y / (12.3 * k) + 1.7 * np.sin(X / (25.9 * k)))
         + 0.4 * np.sin(X / (7.9 * k) + Y / (9.1 * k)) * np.sin(Y / (8.3 * k) - X / (11.7 * k)))
    n = 0.5 + 0.35 * n
    band = np.exp(-((rho - 0.66) / 0.2) ** 2)
    ridge = 0.5 * band * n * (0.75 + 0.25 * np.sin(3 * theta + 0.8))
    hills = 0.05 * n * (rho > 0.38)
    coast = np.clip((_radius(theta) - rho) / 0.12, 0, 1)
    return np.where(inside, (peak + ridge + hills) * coast, 0.0)


def forest(X, Y):
    """Densita' dei boschi sull'isola (0..1): pianure dei territori esterni."""
    rho, theta, d = polar(X, Y)
    inside = rho <= _radius(theta) * 0.9
    n = np.sin(X / (17.0 * SCALE) + np.sin(Y / 23.0)) * np.sin(Y / (19.0 * SCALE) + np.cos(X / 29.0))
    return np.where(inside & (d > CORE_R + 6 * SCALE), np.clip(n * 1.6, 0, 1), 0.0)
