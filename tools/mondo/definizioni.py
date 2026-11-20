"""Lettura di regioni_mondo.txt e dello startpos originale (nomi, confinanti, ordine delle regioni europee)."""
import re
from dataclasses import dataclass, field


@dataclass
class Def:
    kind: str                 # 'EU', 'TERRA', 'MARE'
    id: str
    it: str = ''
    en: str = ''
    castle: tuple = None      # (lat, lon)
    seeds: list = field(default_factory=list)
    culture: str = ''
    terrain: str = ''
    arch: str = ''
    income: int = 0
    goods: list = field(default_factory=list)
    resources: list = field(default_factory=list)
    garrison: list = field(default_factory=list)
    rebels: int = 62
    speed: float = 1.0

    @property
    def is_sea(self):
        return self.kind == 'MARE'

    @property
    def is_new(self):
        return self.kind == 'TERRA' or (self.kind == 'MARE' and self.it != '')


def _ll(text):
    a, b = text.split(',')
    return float(a), float(b)


def _seeds(text):
    return [_ll(s) for s in text.split(';') if s.strip()]


def load(path):
    out = []
    for raw in open(path, encoding='utf-8'):
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        f = line.split('|')
        k = f[0]
        if k == 'EU':
            d = Def('EU', f[1], castle=_ll(f[2]), seeds=_seeds(f[3]))
            if len(f) > 4 and f[4]:
                d.speed = float(f[4])
        elif k == 'TERRA':
            d = Def('TERRA', f[1], it=f[2], en=f[3], castle=_ll(f[4]), seeds=_seeds(f[5]), culture=f[6], terrain=f[7],
                    arch=f[8], income=int(f[9]), goods=[g for g in f[10].split(',') if g],
                    resources=[r for r in f[11].split(',') if r],
                    garrison=[(u.split(':')[0], int(u.split(':')[1])) for u in f[12].split(',') if u],
                    rebels=int(f[13]))
            if len(f) > 14 and f[14]:
                d.speed = float(f[14])
        elif k == 'MARE':
            d = Def('MARE', f[1], it=f[2], en=f[3], seeds=_seeds(f[4]))
            if len(f) > 5 and f[5]:
                d.speed = float(f[5])
        else:
            raise ValueError('riga sconosciuta: ' + line)
        out.append(d)
    ids = [d.id for d in out]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        raise ValueError('id ripetuti: %s' % dup)
    return out


def startpos_commands(path):
    """Comandi dello startpos: lista di (nome, argomenti), commenti // tolti."""
    cmds = []
    for raw in open(path, encoding='latin-1'):
        line = raw.split('//')[0].strip()
        m = re.match(r'([A-Za-z_]+)::\s*(.*)', line)
        if not m:
            continue
        args = [a.strip('"') for a in re.findall(r'"[^"]*"|\S+', m.group(2))]
        cmds.append((m.group(1), args))
    return cmds


def original_neighbours(cmds):
    pairs = set()
    for name, a in cmds:
        if name == 'SetNeighbours':
            r = a[0].upper()
            for n in a[1:]:
                pairs.add(tuple(sorted((r, n.upper()))))
    return pairs
