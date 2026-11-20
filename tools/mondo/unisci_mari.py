"""Unisce zone di mare della mappa del mondo (richiesta di Federico del 16/11/2026: Mediterraneo meno frammentato).

Legge data/mappa_mondo/mari_uniti.cfg (zona tolta = zona che la assorbe) e riscrive in <uscita>:
- regioni.png e regioni_auror.png: i pixel delle zone tolte prendono l'indice della zona che le assorbe;
- regioni.npy e regioni_auror.npy (per confini_mondo.py);
- mondo.json: senza le zone tolte, pixel sommati alla zona che le assorbe;
- startpos_mondo.txt e startpos_atlantide.txt: SetNeighbours con le zone sostituite, senza doppioni ne' se stessa; le righe
  della zona tolta confluiscono in quella della zona che la assorbe; le altre righe della zona tolta (SetOrigin) spariscono.
Poi: python3 confini_mondo.py <uscita>/regioni.npy <uscita>/confini.bin (e regioni_auror.npy -> confini_auror.bin).

Uso: python3 unisci_mari.py <cartella data/mappa_mondo> <uscita>
"""
import json
import os
import re
import sys

import numpy as np
from PIL import Image


def read_aliases(path):
    out = {}
    section = ""
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if not s or s.startswith(";"):
            continue
        if s.startswith("["):
            section = s
            continue
        if section == "[uniti]" and "=" in s:
            k, v = s.split("=", 1)
            out[k.strip().upper()] = v.strip().strip('"').upper()
    return out


def relabel_png(src, dst, npy, mapping):
    img = np.array(Image.open(src).convert("RGB"))
    idx = img[:, :, 0].astype(np.int32) + 256 * img[:, :, 1].astype(np.int32)
    for old, new in mapping.items():
        idx[idx == old] = new
    out = np.zeros_like(img)
    out[:, :, 0] = idx % 256
    out[:, :, 1] = idx // 256
    Image.fromarray(out, "RGB").save(dst, optimize=True)
    np.save(npy, idx.astype(np.uint16))
    return idx


def merge_neighbours(text, aliases):
    lines = text.replace("\r", "").split("\n")
    heads = {}
    order = []
    out = []
    for line in lines:
        if not line.startswith("SetNeighbours::"):
            args = line.split("::", 1)[1].split() if "::" in line else []
            if args and args[0].strip('"').upper() in aliases:
                continue   # SetOrigin e simili della zona tolta: la zona non c'e' piu'
            for old, new in aliases.items():
                line = re.sub(r"\b%s\b" % old, new, line)
            out.append(line)
            continue
        parts = line.split()[1:]
        head = aliases.get(parts[0], parts[0])
        if head not in heads:
            heads[head] = []
            order.append(head)
            out.append(("NB", head))
        for p in parts[1:]:
            q = aliases.get(p, p)
            if q != head and q not in heads[head]:
                heads[head].append(q)
    final = []
    for item in out:
        if isinstance(item, tuple):
            final.append("SetNeighbours::\t" + item[1] + "\t" + "\t".join(sorted(heads[item[1]])))
        else:
            final.append(item)
    return "\n".join(final)


def main(src, dst):
    os.makedirs(dst, exist_ok=True)
    aliases = read_aliases(os.path.join(src, "mari_uniti.cfg"))
    info = json.load(open(os.path.join(src, "mondo.json")))
    by_id = {r["id"]: r for r in info["regions"]}
    mapping = {}
    for old, new in aliases.items():
        if old not in by_id or new not in by_id:
            sys.exit("zona sconosciuta: %s -> %s" % (old, new))
        mapping[by_id[old]["index"]] = by_id[new]["index"]
        by_id[new]["pixels"] = by_id[new].get("pixels", 0) + by_id[old].get("pixels", 0)
    info["regions"] = [r for r in info["regions"] if r["id"] not in aliases]
    json.dump(info, open(os.path.join(dst, "mondo.json"), "w"), separators=(", ", ": "))
    for name in ["regioni", "regioni_auror"]:
        idx = relabel_png(os.path.join(src, name + ".png"), os.path.join(dst, name + ".png"),
                          os.path.join(dst, name + ".npy"), mapping)
        left = [k for k in mapping if (idx == k).any()]
        print(name, "indici rimasti delle zone tolte:", left)
    for name in ["startpos_mondo.txt", "startpos_atlantide.txt"]:
        text = open(os.path.join(src, name), encoding="latin-1").read()
        merged = merge_neighbours(text, aliases)
        for old in aliases:
            if re.search(r"\b%s\b" % old, merged):
                print("ATTENZIONE: %s ancora in %s" % (old, name))
        open(os.path.join(dst, name), "w", encoding="latin-1", newline="\n").write(merged)
    print("zone tolte:", len(aliases))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
