# -*- coding: utf-8 -*-
"""Dati dello scenario storico (ADR-068): Danesi, Norvegesi e Svedesi come nella XL 3.0 originale, senza la mod Auror.

L'installazione contiene la XL 3.0 con la mod Auror applicata (_MOD_BACKUP_ORIG/auror_apply.py del gioco originale, poi il
potenziamento del 7/11 e la caracca del 9/11). Lo script estrae i file puliti dall'installer della XL (VH_MTW_XL3_Full.exe,
Clickteam Install Creator), li confronta con quelli dell'installazione e scrive in data/scenari/storico/:

- startpos_aggiunte.txt: righe XL originali che lo startpos filtrato (ScenarioFilter.startpos: via le righe «// MOD Auror», di
  nuovo attive quelle commentate dalla mod) non ha: proprietari delle quattro regioni nordiche, edifici, risorse, merci, tesoro,
  re iniziale e colori dei Danesi. Lo spostamento al 1000 (data d'inizio, anni di nascita degli agenti) resta, come in tutto il
  remake;
- unita.json / edifici.json: per ogni voce del prod XL Early le celle diverse dall'originale (colonna -> valore originale);
- eroi.json: righe del file degli eroi da rimettere com'erano (nomi reali, re e generali famosi danesi).

Uso: python3 tools/scenario_storico.py <cartella del gioco> <VH_MTW_XL3_Full.exe> [<cartella di uscita>]
"""
import difflib, json, os, re, struct, sys, zlib, bz2
from collections import Counter

MARK = 'MOD Auror'


# ------------------------------------------------------------------------------------------- installer Clickteam (XL 3.0)

def clickteam_files(exe, wanted):
    """{nome (minuscolo, con /) -> bytes} dei file `wanted` dell'installer: blocchi id/flag/dimensione dopo la firma
    77 77 67 54 29 48 in coda all'eseguibile; 0x143A = elenco dei file (bzip2/zlib), 0x7F7F = dati, un pezzo compresso per file
    (4 byte di controllo, 1 byte di metodo: 1 zlib, 2 bzip2)."""
    data = open(exe, 'rb').read()
    pe = struct.unpack('<I', data[0x3c:0x40])[0]
    nsec = struct.unpack('<H', data[pe + 6:pe + 8])[0]
    opt = struct.unpack('<H', data[pe + 20:pe + 22])[0]
    end = 0
    for i in range(nsec):
        s = pe + 24 + opt + 40 * i
        size, off = struct.unpack('<II', data[s + 16:s + 24])
        end = max(end, off + size)
    pos = data.find(b'wwgT)H', end)
    pos += 6
    blocks = {}
    while pos + 8 <= len(data):
        bid, _flags, size = struct.unpack('<HHI', data[pos:pos + 8])
        blocks[bid] = (pos + 8, size)
        pos += 8 + size
        if bid == 0x7F7F:
            break
    lp, ls = blocks[0x143A]
    raw = data[lp:lp + ls]
    listing = bz2.decompress(raw[5:]) if raw[4] == 2 else zlib.decompress(raw[5:])
    base = blocks[0x7F7F][0]
    want = {w.lower().replace('\\', '/') for w in wanted}
    out = {}
    p = 4
    while p < len(listing):
        n = struct.unpack('<H', listing[p:p + 2])[0]
        if n == 0:
            break
        e = listing[p:p + n]
        name = e[0x40:].split(b'\0')[0].decode('latin-1').lower().replace('\\', '/')
        size, off, csize = struct.unpack('<III', e[0x18:0x24])
        if name in want:
            chunk = data[base + off:base + off + csize + 64]
            body = bz2.BZ2Decompressor().decompress(chunk[5:]) if chunk[4] == 2 else (
                zlib.decompressobj().decompress(chunk[5:]) if chunk[4] == 1 else chunk[5:5 + size])
            out[name] = body[:size]
        p += n
    return out


# ------------------------------------------------------------------------------------------------------------- testo e TSV

def dec(b):
    return b.decode('latin-1')


def unq(f):
    if len(f) >= 2 and f.startswith('"') and f.endswith('"'):
        return f[1:-1].replace('""', '"')
    return f


def split_record(rec):
    out, pend, op = [], '', False
    for part in rec.split('\t'):
        if op:
            pend += '\t' + part
            if pend.count('"') % 2 == 0:
                out.append(unq(pend)); op = False
        elif part.startswith('"') and part.count('"') % 2 == 1:
            pend, op = part, True
        else:
            out.append(unq(part))
    if op:
        out.append(unq(pend))
    return out


def data_rows(text):
    lines = text.replace('\r', '').split('\n'); rows = []; i = 0
    while i < len(lines):
        rec = lines[i]; i += 1
        while rec.count('"') % 2 == 1 and i < len(lines):
            rec += '\n' + lines[i]; i += 1
        if rec.strip():
            rows.append(split_record(rec))
    s = [k for k, r in enumerate(rows) if r and r[0].strip().upper() == 'DATA START'][0]
    return rows[s + 1:]


def table(text, key_col):
    out = {}
    for r in data_rows(text):
        if len(r) > key_col and r[key_col].strip() and not r[0].startswith('//'):
            out.setdefault(r[key_col].strip().upper(), r)
    return out


def cell_diffs(cur, orig):
    """{voce: {colonna: valore originale}} delle celle diverse (confronto senza spazi ai bordi)."""
    out = {}
    for key, r in cur.items():
        o = orig.get(key)
        if o is None:
            continue
        ch = {}
        for col in range(max(len(r), len(o))):
            a = r[col].strip() if col < len(r) else ''
            b = o[col].strip() if col < len(o) else ''
            if a != b:
                ch[str(col)] = b
        if ch:
            out[key] = ch
    return out


# ---------------------------------------------------------------------------------------------------------------- startpos

def filtered_startpos(text):
    """Copia in Python di ScenarioFilter.startpos senza aggiunte (per calcolare le aggiunte)."""
    L = text.replace('\r', '').split('\n')
    def dis(s):
        return s.startswith('//') and MARK in s and ('fazione disattivata' in s or 'regione agli Auror' in s)
    def unc(s):
        c = s.strip()[2:]; i = c.find('//')
        return (c[:i] if i >= 0 else c).strip()
    rev = set()
    for l in L:
        s = l.strip()
        if dis(s):
            m = re.match(r'^\s*SetActiveFaction::\s+(FN_\w+)', unc(s))
            if m:
                rev.add(m.group(1).upper())
    out, skip = [], False
    for l in L:
        s = l.strip()
        if skip:
            if s.startswith('MakeUnit') and s.endswith('//FN_DANISH'):
                continue
            skip = False
        if s.startswith('//'):
            if s.startswith('// MOD Auror:') and ('esercito' in s or 'flotta' in s):
                skip = True
            elif dis(s):
                out.append(unc(s))
            else:
                m = re.match(r'^//\s*AddHeir::\s+(FN_\w+)', s)
                out.append(s[2:].strip() if m and m.group(1).upper() in rev else l)
            continue
        at = s.find('//')
        if at >= 0 and MARK in s[at:]:
            m = re.match(r'^\s*PlaceLeader::\s+(\S+)\s+(FN_\w+)\s*//\s*MOD Auror \(era (\w+)\)', s)
            if m:
                out.append('PlaceLeader:: %s\t\t%s' % (m.group(3), m.group(2)))
            continue
        out.append(l)
    return out


def norm(line):
    c = line.split('//')[0].strip()
    return re.sub(r'\s+', ' ', c)


def startpos_additions(cur_text, xl_text):
    have = Counter(norm(l) for l in filtered_startpos(cur_text) if norm(l))
    out = ['// Scenario storico (ADR-068): righe della XL 3.0 originale (installer VH_MTW_XL3_Full.exe) che lo startpos',
           '// dell\'installazione, tolta la mod Auror, non ha piu\'. Generato da tools/scenario_storico.py: non modificare a mano.']
    skipped = []
    for l in xl_text.replace('\r', '').split('\n'):
        n = norm(l)
        if not n:
            continue
        if have[n] > 0:
            have[n] -= 1
            continue
        # lo spostamento al 1000 resta (data d'inizio e anni di nascita degli agenti, spostati di 80 anni dalla mod)
        if re.match(r'^Set(Start|EarlyPeriodStart|HighPeriodStart|LatePeriodStart)Date::', n) or \
                re.match(r'^MakeUnit:: \S+ (Emissary|Princess|Spy|Assassin|Bishop|Priest|Inquisitor)\b', n):
            skipped.append(n)
            continue
        out.append(l.rstrip())
    return out, skipped


def heroes_rows(cur_text, xl_text):
    a = cur_text.replace('\r', '').split('\n'); b = xl_text.replace('\r', '').split('\n')
    rows = []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == 'replace' and i2 - i1 == j2 - j1:
            for x, y in zip(a[i1:i2], b[j1:j2]):
                rows.append([x.strip(), y.strip()])
        elif tag != 'equal':
            rows.append(['?', '%s %d-%d / %d-%d' % (tag, i1, i2, j1, j2)])
    return rows


def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(1)
    G, EXE = sys.argv[1], sys.argv[2]
    OUT = sys.argv[3] if len(sys.argv) > 3 else os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'scenari', 'storico')
    os.makedirs(OUT, exist_ok=True)
    rd = lambda p: dec(open(os.path.join(G, p), 'rb').read())
    sp = rd('campmap/startpos/EARLY_XL.TXT')
    m = re.search(r'^\s*Prodfiles::\s+UNITPROD\s+"([^"]+)"\s+BUILDINGPROD\s+"([^"]+)"', sp, re.M)
    unit_file, building_file = m.group(1), m.group(2)
    nm = re.search(r'^\s*SetNameData::\s+"?([^"\s]+)', sp, re.M)
    hero_file = 'campmap/names/' + nm.group(1).replace('\\', '/').split('/')[-1]
    xl = clickteam_files(EXE, ['campmap/startpos/EARLY_XL.TXT', unit_file, building_file, hero_file])
    get = lambda p: dec(xl[p.lower()])
    add, skipped = startpos_additions(sp, get('campmap/startpos/EARLY_XL.TXT'))
    units = cell_diffs(table(rd(unit_file), 0), table(get(unit_file), 0))
    # Eccezione voluta: le unita' degli Ordini non hanno edificio nel file originale (nell'originale non si arruolano, arrivano
    # con gli eventi), ma nel remake un requisito vuoto vuol dire «ovunque». Resta la Casa del Capitolo che il remake da' loro
    # in entrambi gli scenari (requisito per tutte le fazioni dell'elenco, non solo per i Danesi).
    kept = []
    for name, cells in list(units.items()):
        if cells.get('16') == '' and 'CHAPTER_HOUSE' in table(rd(unit_file), 0)[name][16]:
            del cells['16']; kept.append(name)
            if not cells:
                del units[name]
    blds = cell_diffs(table(rd(building_file), 1), table(get(building_file), 1))
    rows = heroes_rows(rd(hero_file), get(hero_file))
    bad = [r for r in rows if r[0] == '?']
    if bad:
        print('ATTENZIONE: righe degli eroi non allineate', bad)
    rows = [r for r in rows if r[0] != '?']
    with open(os.path.join(OUT, 'startpos_aggiunte.txt'), 'wb') as f:
        f.write(('\r\n'.join(add) + '\r\n').encode('latin-1'))
    with open(os.path.join(OUT, 'unita.json'), 'w', encoding='utf-8') as f:
        json.dump({'file': unit_file, 'fonte': os.path.basename(EXE), 'unita': units}, f, ensure_ascii=False, indent=1, sort_keys=True)
    with open(os.path.join(OUT, 'edifici.json'), 'w', encoding='utf-8') as f:
        json.dump({'file': building_file, 'fonte': os.path.basename(EXE), 'edifici': blds}, f, ensure_ascii=False, indent=1, sort_keys=True)
    with open(os.path.join(OUT, 'eroi.json'), 'w', encoding='utf-8') as f:
        json.dump({'file': os.path.basename(hero_file), 'fonte': os.path.basename(EXE), 'righe': rows}, f, ensure_ascii=False, indent=1)
    print('startpos: %d righe aggiunte, %d lasciate allo spostamento al 1000' % (len(add) - 2, len(skipped)))
    print('unita\' corrette: %d, edifici: %d, righe degli eroi: %d' % (len(units), len(blds), len(rows)))
    print('Casa del Capitolo lasciata a: %s' % ', '.join(sorted(kept)))


if __name__ == '__main__':
    main()
