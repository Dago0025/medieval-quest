"""Estrae il solo modello di esportazione Windows (windows_release_x86_64.exe) dal .tpz di Godot senza scaricarlo
tutto (1,2 GB): legge lo zip remoto a intervalli espliciti (bytes=a-b) sull'indirizzo finale dopo il reindirizzamento.
Serve nelle sessioni in cui Godot gira in una macchina Linux senza i modelli installati; poi:
    godot --headless --export-release "Windows" "build/MTW Remake.exe"
Uso: python3 tools/estrai_modello_esportazione.py   (circa 10 secondi)
"""
import sys, io, zipfile, urllib.request, os
URL="https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
# URL finale dopo il reindirizzamento
req=urllib.request.Request(URL, headers={"Range":"bytes=0-0"})
r=urllib.request.urlopen(req); final=r.geturl(); total=int(r.headers["Content-Range"].split("/")[1]); r.close()
print("dimensione", total)
class Ranged(io.RawIOBase):
    def __init__(s): s.pos=0
    def seekable(s): return True
    def readable(s): return True
    def tell(s): return s.pos
    def seek(s,o,w=0):
        s.pos = o if w==0 else (s.pos+o if w==1 else total+o); return s.pos
    def read(s,n=-1):
        if n<0: n=total-s.pos
        if n==0 or s.pos>=total: return b""
        end=min(total,s.pos+n)-1
        q=urllib.request.Request(final, headers={"Range":"bytes=%d-%d"%(s.pos,end)})
        d=urllib.request.urlopen(q).read(); s.pos+=len(d); return d
    def readinto(s,b):
        d=s.read(len(b)); b[:len(d)]=d; return len(d)
z=zipfile.ZipFile(io.BufferedReader(Ranged(), buffer_size=1<<20))
name="templates/windows_release_x86_64.exe"
out=os.path.expanduser("~/.local/share/godot/export_templates/4.7.2.stable/")
os.makedirs(out,exist_ok=True)
with z.open(name) as src, open(out+"windows_release_x86_64.exe","wb") as dst:
    while True:
        b=src.read(1<<22)
        if not b: break
        dst.write(b)
open(out+"version.txt","w").write("4.7.2.stable\n")
print(os.path.getsize(out+"windows_release_x86_64.exe"))
