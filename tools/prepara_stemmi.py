"""Stemmi delle fazioni rifatti con AI Playground (Edit by Prompt 2) dagli scudi dell'originale (campmap/shields/*_lge).

Uso:  python tools/prepara_stemmi.py <conversione_pedine> [--solo ST01,ST02] [--cfg]

Per ogni ST##_<fazione>.png di risultati/: toglie il fondo grigio (come tools/prepara_pedine.py), ritaglia lo scudo e lo
mette in assets/stemmi/<fazione minuscola>.png a 136x160 (4 volte lo scudo 34x40, come auror.png), centrato e
appoggiato in basso (gli Auror in auror.png, ST00, rifatto il 15/11 nello stesso stile). Con --cfg scrive le voci in data/fazioni.cfg [stemmi] (gli Auror restano col loro stemma).
ST31 = Danesi dello scenario storico (ADR-068): assets/stemmi/fn_danish.png, in data/fazioni.cfg [stemmi_storico].
"""
import argparse, json, os, re, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepara_pedine import cut_background, bbox   # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = (136, 160)
PAD = 2


def shield(path):
    a = cut_background(np.array(Image.open(path).convert('RGB').convert('RGBA')))
    x0, y0, x1, y1 = bbox(a[..., 3] > 128)
    im = Image.fromarray(a).crop((x0, y0, x1, y1)).convert('RGBa')
    w, h = SIZE[0] - 2 * PAD, SIZE[1] - 2 * PAD
    s = min(w / im.width, h / im.height)
    im = im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
    out = Image.new('RGBa', SIZE, (0, 0, 0, 0))
    out.paste(im, ((SIZE[0] - im.width) // 2, SIZE[1] - PAD - im.height))
    return out.convert('RGBA')


def bianco_e_nero(im, lo=70, hi=185):
    """Stemma Auror: l'IA lo dipinge grigio su grigio; si riportano campo bianco e drago nero (livelli sulla luminosita')."""
    a = np.array(im).astype(float)
    a[..., :3] = np.clip((a[..., :3] - lo) * 255.0 / (hi - lo), 0, 255)
    return Image.fromarray(a.astype(np.uint8))


def write_cfg(factions):
    """Aggiunge o aggiorna in data/fazioni.cfg [stemmi] le voci delle fazioni date, lasciando le altre."""
    p = os.path.join(ROOT, 'data', 'fazioni.cfg')
    text = open(p, encoding='utf-8').read()
    head, sep, rest = text.partition('[stemmi]\n')
    nxt = re.search(r'\n\n\n|\n\[', rest)
    body, tail = (rest[:nxt.start()], rest[nxt.start():]) if nxt else (rest, '')
    lines = [l for l in body.split('\n') if l.strip()]
    entries = {l.split('=', 1)[0]: l for l in lines if not l.startswith(';')}
    for fid in factions:
        entries[fid] = '%s="res://assets/stemmi/%s.png"' % (fid, fid.lower())
    comments = [l for l in lines if l.startswith(';')]
    note = "; stemmi dipinti con AI Playground dagli scudi dell'originale (tools/prepara_stemmi.py, 2026-11-15)"
    if note not in comments:
        comments.append(note)
    keep = [entries.pop('FN_DANISH')] if 'FN_DANISH' in entries else []
    new = comments + keep + [entries[k] for k in sorted(entries)]
    open(p, 'w', encoding='utf-8', newline='\n').write(head + sep + '\n'.join(new) + '\n' + tail)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('conv')
    ap.add_argument('--solo', default='')
    ap.add_argument('--cfg', action='store_true')
    ap.add_argument('--foglio', default='')
    args = ap.parse_args()
    queue = json.load(open(os.path.join(args.conv, '_strumenti', 'coda.json'), encoding='utf-8'))
    only = set(x for x in args.solo.split(',') if x)
    done = []
    for e in queue:
        if e['tipo'] != 'stemma' or (only and e['id'] not in only):
            continue
        res = os.path.join(args.conv, 'risultati', os.path.basename(e['file']))
        if not os.path.isfile(res):
            continue
        im = shield(res)
        # gli Auror (ST00) tengono il loro file; ST31 sono i Danesi dello scenario storico (ADR-068) -> fn_danish.png
        auror = e['id'] == 'ST00'
        name = 'auror' if auror else e['fazione'].lower()
        if auror:
            im = bianco_e_nero(im)
        im.save(os.path.join(ROOT, 'assets', 'stemmi', name + '.png'))
        done.append((e['fazione'], im))
        print(e['id'], e['fazione'])
    if args.cfg and done:
        write_cfg([f for f, _ in done if f != 'FN_DANISH'])   # FN_DANISH: auror.png in [stemmi], fn_danish.png in [stemmi_storico]
    if args.foglio and done:
        sheet = Image.new('RGBA', (min(len(done), 10) * 146, ((len(done) + 9) // 10) * 170), (60, 60, 60, 255))
        for i, (_, im) in enumerate(done):
            sheet.alpha_composite(im, ((i % 10) * 146 + 5, (i // 10) * 170 + 5))
        sheet.save(args.foglio)


if __name__ == '__main__':
    main()
