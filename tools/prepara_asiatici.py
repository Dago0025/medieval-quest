"""Grafica dei popoli asiatici e del Dharma (22/11/2026) dalle immagini approvate di AI Playground.

Uso:  python tools/prepara_asiatici.py <cartella con le immagini CODICE.png> [--foglio <file.png>]

Codici (un file per codice, quelli che mancano si saltano):
  AG_EMISSARY, AG_SPY, AG_ASSASSIN, AG_MONK, AG_PRINCESS   carte degli agenti della cultura Asian (1024x1024 su grigio):
      assets/rifatti/campmap/review_panel/agents/asian/<id>.png (200x200; nella scheda dell'agente c'e' il ritratto)
  DH_TEMPLE, DH_MONASTERY, DH_PAGODA                       edifici del Dharma (1024x768 su grigio, dipinti sulla base
      della chiesa, del monastero e della cattedrale): review_panel/buildings/asian/<etichetta>.png (272x200)
  JC_KEEP, JC_CASTLE, JC_CITADEL, JC_FORTRESS              castelli giapponesi (stile «japanese» di CastleStyle)
  ZC_KEEP ... ZC_FORTRESS, IC_KEEP ... IC_FORTRESS        castelli aztechi e inca (stili «aztec», «inca», 22/11/2026)
  KC_KEEP ... KC_FORTRESS                                  castelli saheliani del Kanem (stile «kanem», ADR-125)
  MC_FORT ... MC_FORTRESS                                  castelli mississippiani (stile «mississippian», ADR-126)
  HC_*, XC_*                                               castelli di Chola (stile «indian») e Khmer («khmer»)
  <prefisso>_FORT                                          forte di ogni stile; RC_FORT villaggio dei ribelli (ADR-126)
  AK_<AGENTE>, AM_<AGENTE>                                 carte degli agenti del Kanem e dei Mississippiani
  CC_KEEP, CC_CASTLE, CC_CITADEL, CC_FORTRESS              castelli cinesi (stile «chinese»), 1024x768 su grigio:
      icona review_panel/buildings/<stile>/<grado>.png (272x200) e pedina pieces/buildings/<stile>/<grado>.png (stendardo,
      aste e ombra del castello dello stesso grado dell'originale, con il castello dipinto al posto delle mura)
Le pedine degli eserciti, delle flotte e degli agenti si preparano con tools/prepara_pedine.py (voci PD67-PD82).
"""
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prepara_unita as pu  # noqa: E402
from prepara_edifici import cut_grey, BASE_KEEP  # noqa: E402
from prepara_castelli_mappa import build  # noqa: E402
from prepara_fortezza_auror import icon_from  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "rifatti", "campmap")
AGENTS = {"AG_EMISSARY": "emissary", "AG_SPY": "spy", "AG_ASSASSIN": "assassin", "AG_MONK": "monk",
          "AG_PRINCESS": "princess"}
DHARMA = {"DH_TEMPLE": "dharma temple", "DH_MONASTERY": "dharma monastery", "DH_PAGODA": "great pagoda"}
STYLES = {"JC": "japanese", "CC": "chinese", "ZC": "aztec", "IC": "inca", "KC": "kanem", "MC": "mississippian",
          "RC": "rebel", "HC": "indian", "XC": "khmer"}
# carte degli agenti per cultura: prefisso -> cartella di review_panel/agents
AGENT_CULTURES = {"AG": "asian", "AK": "african", "AM": "mississippian", "AI": "indian", "AX": "khmer", "AA": "aztec", "AN": "inca"}
AGENT_NAMES = ["EMISSARY", "SPY", "ASSASSIN", "MONK", "PRINCESS", "MULLAH", "ULAMA", "SHAMAN"]
TIERS = ["FORT", "KEEP", "CASTLE", "CITADEL", "FORTRESS"]


def save(img, *parts):
    d = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(d), exist_ok=True)
    img.save(d, optimize=True)
    return img


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__); sys.exit(2)
    sheet = None
    if "--foglio" in args:
        i = args.index("--foglio"); sheet = args[i + 1]; del args[i:i + 2]
    src = args[0]
    done = []

    def have(code):
        p = os.path.join(src, code + ".png")
        return p if os.path.isfile(p) else ""

    for prefix, folder in AGENT_CULTURES.items():
        for name in AGENT_NAMES:
            p = have("%s_%s" % (prefix, name))
            if p:
                art = pu.cut(p)
                done.append(save(pu.card_from(art), "review_panel", "agents", folder, name.lower() + ".png"))
    for code, label in DHARMA.items():
        p = have(code)
        if p:
            done.append(save(icon_from(cut_grey(p, BASE_KEEP)), "review_panel", "buildings", "asian", label + ".png"))
    for prefix, style in STYLES.items():
        for tier in TIERS:
            p = have("%s_%s" % (prefix, tier))
            if not p:
                continue
            done.append(save(icon_from(cut_grey(p, BASE_KEEP)), "review_panel", "buildings", style, tier.lower() + ".png"))
            _, piece = build(tier, p)
            done.append(save(piece, "pieces", "buildings", style, tier.lower() + ".png"))
    print("immagini scritte:", len(done))
    if sheet and done:
        w = sum(im.width + 8 for im in done)
        h = max(im.height for im in done)
        sh = Image.new("RGBA", (w, h), (178, 160, 120, 255))
        x = 0
        for im in done:
            sh.alpha_composite(im.convert("RGBA"), (x, h - im.height))
            x += im.width + 8
        sh.save(sheet)


if __name__ == "__main__":
    main()
