#!/usr/bin/env python3
"""Controllo delle traduzioni (ADR-066).

Uso (dalla cartella del progetto):
  python tools/testi_lingua.py              riepilogo: frasi di Lang.t senza traduzione, voci inutilizzate, segnaposto diversi
  python tools/testi_lingua.py --sospetti   anche le stringhe italiane del codice non avvolte in Lang.t (euristica)
  python tools/testi_lingua.py --file src/map/campaign_ui_text.gd --sospetti   solo quei file
  python tools/testi_lingua.py --mancanti mancanti.tsv   scrive le frasi senza traduzione (italiano TAB vuoto)
  python tools/testi_lingua.py --tabella data/lingue/parti/X.tsv ...   unisce altre tabelle a en.tsv per il controllo

Le frasi del codice sono i letterali passati direttamente a Lang.t("...") (anche su piu' righe con la concatenazione
implicita non c'e': un letterale per chiamata). Le stringhe in costanti tradotte al momento dell'uso (Lang.t(pair[1]))
non si vedono qui: vanno elencate a mano in data/lingue/en.tsv e il test test_lingua le controlla con LANG_EXTRA.
"""
import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.path.join(ROOT, "data", "lingue", "en.tsv")
SCAN = ["src", "scenes"]

LIT = r'"((?:[^"\\\n]|\\.)*)"'
CALL = re.compile(r'Lang\.t\(\s*' + LIT + r'\s*\)')
ANY_LIT = re.compile(LIT)
PH = re.compile(r'%(?:%|[-+ 0#]*\d*(?:\.\d+)?[sdifxXc])')


def gd_unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "'": "'", "\\": "\\"}.get(n, "\\" + n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tsv_unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s) and s[i + 1] in "nt\\":
            out.append({"n": "\n", "t": "\t", "\\": "\\"}[s[i + 1]])
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tsv_escape(s):
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")


def load_table(path=TABLE):
    table = {}
    if not os.path.exists(path):
        return table
    with open(path, encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.rstrip("\n").rstrip("\r")
            if not line.strip() or line.startswith("#"):
                continue
            if "\t" not in line:
                print(f"en.tsv:{n}: riga senza TAB", file=sys.stderr)
                continue
            k, v = line.split("\t", 1)
            table[tsv_unescape(k)] = tsv_unescape(v)
    return table


def gd_files(only=None):
    if only:
        return [os.path.join(ROOT, p) if not os.path.isabs(p) else p for p in only]
    out = []
    for d in SCAN:
        for root, _, files in os.walk(os.path.join(ROOT, d)):
            out += [os.path.join(root, f) for f in files if f.endswith(".gd")]
    return sorted(out)


def code_part(line):
    """La riga senza commento (# fuori dalle stringhe)."""
    in_str, i = False, 0
    while i < len(line):
        c = line[i]
        if c == "\\" and in_str:
            i += 2
            continue
        if c == '"':
            in_str = not in_str
        elif c == "#" and not in_str:
            return line[:i]
        i += 1
    return line


SKIP_CALLS = ("push_warning", "push_error", "print(", "printerr", "assert(", "errors.append", "warnings.append",
              "load(", "preload(", "has_method", "get_node", "connect(", "emit_signal", "Lang.pick")


def looks_italian(t):
    if t.startswith(("res://", "user://")) or "/" in t and " " not in t:
        return False
    if re.fullmatch(r"[A-Z0-9_]+", t) or re.fullmatch(r"[a-z0-9_]+", t):
        return False
    return bool(re.search(r"[a-zàèéìòù]{2,}\s+[a-zàèéìòù%]", t, re.I) or re.match(r"[A-ZÀ-Ú][a-zàèéìòù']{2,}", t))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sospetti", action="store_true")
    ap.add_argument("--file", nargs="*")
    ap.add_argument("--mancanti")
    ap.add_argument("--tabella", nargs="*", default=[], help="altre tabelle TSV da unire (es. data/lingue/parti/X.tsv)")
    a = ap.parse_args()
    table = load_table()
    for extra in a.tabella:
        table.update(load_table(os.path.join(ROOT, extra) if not os.path.isabs(extra) else extra))
    used = {}
    suspects = []
    for path in gd_files(a.file):
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                code = code_part(line)
                if code.lstrip().startswith("##"):
                    continue
                spans = []
                for m in CALL.finditer(code):
                    used.setdefault(gd_unescape(m.group(1)), f"{rel}:{n}")
                    spans.append(m.span(1))
                if not a.sospetti:
                    continue
                if any(k in code for k in SKIP_CALLS):
                    continue
                for m in ANY_LIT.finditer(code):
                    if any(s[0] <= m.start(1) < s[1] for s in spans):
                        continue
                    t = gd_unescape(m.group(1))
                    if looks_italian(t) and t not in table:
                        suspects.append(f"{rel}:{n}: {t}")
    missing = [k for k in used if k not in table]
    bad_ph = [k for k in used if k in table and sorted(PH.findall(k)) != sorted(PH.findall(table[k]))]
    print(f"frasi in Lang.t: {len(used)}  tradotte: {len(used) - len(missing)}  senza traduzione: {len(missing)}")
    for k in missing[:200]:
        print(f"  MANCA  {used[k]}: {k!r}")
    for k in bad_ph:
        print(f"  SEGNAPOSTO  {used[k]}: {k!r} -> {table[k]!r}")
    if a.sospetti:
        print(f"stringhe italiane non avvolte (euristica): {len(suspects)}")
        for s in suspects:
            print("  " + s)
    if a.mancanti:
        with open(a.mancanti, "w", encoding="utf-8") as f:
            for k in missing:
                f.write(tsv_escape(k) + "\t\n")
    return 1 if missing or bad_ph else 0


if __name__ == "__main__":
    sys.exit(main())
