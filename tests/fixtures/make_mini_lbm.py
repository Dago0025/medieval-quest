"""Genera mini.lbm: un IFF PBM 8x4 con BODY compresso ByteRun1 e palette di 4 colori.
Uso: python3 -I make_mini_lbm.py   (scrive mini.lbm accanto allo script)

Pixel attesi (indice di palette), righe dall'alto:
  riga 0: 0 0 0 0 0 0 0 0
  riga 1: 1 2 3 0 1 2 3 0
  riga 2: 2 2 2 3 3 0 0 1
  riga 3: 1 1 1 1 2 2 2 2
Palette: 0 = (255,0,255), 1 = (255,0,0), 2 = (0,255,0), 3 = (0,0,255).
Il BODY contiene: una ripetizione (riga 0), un blocco letterale (riga 1), una
ripetizione e un letterale misti (riga 2), un byte NOP (128) e una ripetizione
di 5 uno che attraversa il confine tra la riga 2 e la riga 3.
"""
import os
import struct

W, H = 8, 4
PIXELS = [
    [0, 0, 0, 0, 0, 0, 0, 0],
    [1, 2, 3, 0, 1, 2, 3, 0],
    [2, 2, 2, 3, 3, 0, 0, 1],
    [1, 1, 1, 1, 2, 2, 2, 2],
]
PALETTE = [(255, 0, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255)]


def run(count, value):
    return bytes([257 - count, value])


def literal(values):
    return bytes([len(values) - 1]) + bytes(values)


body = b"".join([
    run(8, 0),                       # riga 0
    literal([1, 2, 3, 0, 1, 2, 3, 0]),  # riga 1
    run(3, 2), run(2, 3),            # riga 2: 2 2 2 3 3
    bytes([128]),                    # NOP
    run(2, 0),                       # riga 2: 0 0
    run(5, 1),                       # riga 2 (ultimo) + riga 3 (primi 4): 1 1 1 1 1
    run(4, 2),                       # riga 3: 2 2 2 2
])

flat = [p for row in PIXELS for p in row]


def unpack(data):
    out = bytearray()
    i = 0
    while i < len(data):
        n = data[i]
        i += 1
        if n < 128:
            out += data[i:i + n + 1]
            i += n + 1
        elif n > 128:
            out += bytes([data[i]]) * (257 - n)
            i += 1
    return list(out)


assert unpack(body) == flat, unpack(body)


def chunk(tag, payload):
    pad = b"\x00" if len(payload) & 1 else b""
    return tag + struct.pack(">I", len(payload)) + payload + pad


bmhd = struct.pack(">HHhhBBBBHBBhh", W, H, 0, 0, 8, 0, 1, 0, 0, 1, 1, W, H)
cmap = b"".join(bytes(c) for c in PALETTE)
# chunk ANNO di lunghezza dispari: serve a provare il byte di riempimento
anno = chunk(b"ANNO", b"abc")
form = b"PBM " + chunk(b"BMHD", bmhd) + chunk(b"CMAP", cmap) + anno + chunk(b"BODY", body)
data = b"FORM" + struct.pack(">I", len(form)) + form

path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mini.lbm")
with open(path, "wb") as f:
    f.write(data)
print("scritto", path, len(data), "byte")
