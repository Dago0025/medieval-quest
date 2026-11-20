"""Parser dei file prod (TSV con celle tra virgolette multilinea) di MTW.
Uso: import tsvload; rows = tsvload.load(path)  # lista di righe (lista di celle str)
Il file e' cp1252/CRLF; le celle possono contenere a capo se tra virgolette."""
import csv, io
def load(path):
    raw = open(path, 'rb').read().decode('cp1252')
    return list(csv.reader(io.StringIO(raw, newline=''), delimiter='\t', quotechar='"'))
