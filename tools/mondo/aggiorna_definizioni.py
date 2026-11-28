"""Scrive in regioni_mondo.txt le regioni nuove di nuove_regioni.py (28/11/2026): semi e castelli nuovi delle regioni
esistenti che cedono territorio, nomi cambiati, righe TERRA delle regioni nuove dopo l'ultima regione di terra.

Uso: python3 aggiorna_definizioni.py <regioni_mondo.txt>   (riscrive il file; si puo' rilanciare: le regioni gia'
presenti non si aggiungono due volte)
"""
import sys

import nuove_regioni as N


def main(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    by_id = {}
    last_terra = 0
    for i, line in enumerate(lines):
        f = line.split('|')
        if f[0] == 'TERRA':
            by_id[f[1]] = i
            last_terra = i
    # regioni esistenti
    for rid, seeds in N.SEMI.items():
        i = by_id[rid]
        f = lines[i].split('|')
        f[5] = seeds
        lines[i] = '|'.join(f)
    for rid, (it, en, castle) in N.NOMI.items():
        i = by_id[rid]
        f = lines[i].split('|')
        f[2], f[3] = it, en
        if castle:
            f[4] = castle
        lines[i] = '|'.join(f)
    # regioni nuove
    new = []
    for rid, it, en, castle, seeds, parent, over in N.NUOVE:
        if rid in by_id:
            i = by_id[rid]
            del lines[i]
            by_id = {k: (v - 1 if v > i else v) for k, v in by_id.items() if k != rid}
            last_terra -= 1
        p = lines[by_id[parent]].split('|')
        f = ['TERRA', rid, it, en, castle, seeds,
             over.get('cultura', p[6]), over.get('terreno', p[7]), over.get('arch', p[8]),
             str(over.get('rendita', p[9])), over.get('merci', p[10]), over.get('risorse', p[11]),
             over.get('guarnigione', p[12]), str(over.get('ribelli', p[13]))]
        if 'velocita' in over:
            f.append(str(over['velocita']))
        new.append('|'.join(f))
    head = ['', '# ---------------------------------------------------------------- regioni nuove del 28/11/2026',
            '# (tools/mondo/nuove_regioni.py: frammentazione degli altri continenti, 221 regioni fuori Europa)']
    # togli un blocco vecchio dello stesso tipo se il file e' gia' stato aggiornato
    if head[1] in lines:
        k = lines.index(head[1])
        del lines[k - 1:k + 2]
        last_terra = max(i for i, l in enumerate(lines) if l.startswith('TERRA|'))
    lines[last_terra + 1:last_terra + 1] = head + new
    open(path, 'w', encoding='utf-8').write('\n'.join(lines))
    print('regioni nuove', len(new))


if __name__ == '__main__':
    main(sys.argv[1])
