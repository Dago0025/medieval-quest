"""Tavole dipinte dei luoghi leggendari (richiesta di Federico del 26/11/2026): dalle immagini di AI Playground
(<media>/luoghi/L_<ID>.png, prompt nel doc di progetto prompt/luoghi_leggendari.md) a assets/luoghi/<id>.png, 1280x720
(16:9, ritaglio centrale come tools/prepara_tavole.py), importate da Godot in WebP con perdita (come le scene degli avvisi).
Il gioco le mostra nella scheda del luogo e come sfondo delle finestre dei suoi eventi; senza tavola usa una tavola generica.

Uso: python tools/prepara_luoghi.py <cartella luoghi di AI Playground> [cartella del progetto]
"""
import os
import sys

from PIL import Image

W, H = 1280, 720
IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=1
compress/high_quality=false
compress/lossy_quality=0.9
mipmaps/generate=false
"""


def main():
    src = sys.argv[1]
    root = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    out_dir = os.path.join(root, "assets", "luoghi")
    os.makedirs(out_dir, exist_ok=True)
    done = 0
    for name in sorted(os.listdir(src)):
        if not (name.startswith("L_") and name.lower().endswith(".png")):
            continue
        site = name[2:-4].lower()
        im = Image.open(os.path.join(src, name)).convert("RGB")
        w, h = im.size
        if w / h > W / H:
            nw = round(h * W / H)
            im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:
            nh = round(w * H / W)
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        im = im.resize((W, H), Image.LANCZOS)
        dest = os.path.join(out_dir, site + ".png")
        im.save(dest, optimize=True)
        if not os.path.exists(dest + ".import"):
            open(dest + ".import", "w", encoding="utf-8", newline="\n").write(IMPORT)
        done += 1
    print(done, "tavole in", out_dir)


if __name__ == "__main__":
    main()
