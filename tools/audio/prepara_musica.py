"""Musiche di Medieval Quest da librerie gratuite (RandomMind, OpenGameArt, CC0).
Uso: python3 prepara_musica.py <sorgenti> <assets/audio/musica> [prefisso]  (es. "Gotico": rifà solo i brani gotici)
Taglio dei silenzi, dissolvenze, volume a due passate (LUFS), OGG a 44,1 kHz (loudnorm porta a 192 kHz se non si indica -ar). Frontend ripete senza stacchi."""
import subprocess, sys, os, json, re, tempfile
src, dst = sys.argv[1], sys.argv[2]
# nome nel gioco: (file sorgente, LUFS)
M = {
 "Frontend":            ("rm_exploration.wav", -18),
 "Euro Strat Summer 1": ("rm_harvest.wav", -20),
 "Euro Strat Summer 2": ("rm_market.wav", -20),
 "Euro Strat Winter 1": ("rm_bards_tale.mp3", -20),
 "Euro Strat Winter 2": ("rm_old_tower_inn.mp3", -20),
 "XL TENSION 1":        ("rm_battle.wav", -20),
 "Minstrel Dance":      ("rm_minstrel.mp3", -20),
 "Kings Feast":         ("rm_kings_feast.mp3", -20),
 "Rejoicing":           ("rm_rejoicing.mp3", -20),
 "Euro Win 1":          ("rm_victory.wav", -18),
 "Euro Lose 1":         ("rm_defeat.wav", -19),
 # tema base dal 26/11/2026: gotico e grimdark, OpenGameArt CC0 (i brani medievali sopra sono in _ia_locale/audio_free/musiche_precedenti)
 "Gotico Menu":          ("au_fantasy_choir_2.wav", -18),      # cesisco (Cesar da Rocha), Fantasy Choir 2
 "Gotico Laments of the War": ("au_laments_of_the_war.flac", -20),  # Cethiel
 "Gotico Fantasy Choir 1": ("au_fantasy_choir_1.wav", -20),    # cesisco
 "Gotico Fantasy Choir 3": ("au_fantasy_choir_3.wav", -20),    # cesisco
 "Gotico Evil Approach":  ("au_evil_approach.wav", -20),       # nene
 "Gotico Warrior Lament": ("rm_lament.mp3", -20),              # RandomMind, Fantasy: Lament for a Warrior's Soul
 "Gotico Graveyard":      ("au_graveyard.wav", -21),           # CleytonKauffman, Kokopelli's Graveyard Theme
 "Gotico Cathedral":      ("au_cathedral.wav", -21),           # Umplix, Cathedral
 "Gotico Chant":          ("au_chant.ogg", -21),               # christislord, Chant (gregoriano)
}
LOOP = {"Frontend", "Gotico Menu"}
def run(*a): return subprocess.run(list(a), capture_output=True, text=True)
def dur(f): return float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f).stdout)
def bounds(f):
    o = run("ffmpeg", "-i", f, "-af", "silencedetect=n=-55dB:d=0.3", "-f", "null", "-").stderr
    D = dur(f); s = [float(x) for x in re.findall(r"silence_start: (-?[\d.]+)", o)]; e = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", o)]
    a = e[0] if s and s[0] <= 0.05 and e else 0.0
    z = s[-1] if s and (len(e) < len(s) or e[-1] >= D - 0.05) and s[-1] > a else D
    return max(0.0, a), z
os.makedirs(dst, exist_ok=True)
solo = sys.argv[3] if len(sys.argv) > 3 else ""
for nome, (f, t) in M.items():
    if solo and not nome.startswith(solo): continue
    p = os.path.join(src, f); a, z = bounds(p); L = z - a; tmp = os.path.join(tempfile.gettempdir(), f"_m_{os.getpid()}.wav")
    if nome in LOOP:
        X = 4.0
        flt = (f"[0:a]atrim={a}:{z},asetpts=PTS-STARTPTS,asplit=2[x][y];[x]atrim={X},asetpts=PTS-STARTPTS[c];"
               f"[y]atrim=0:{X},asetpts=PTS-STARTPTS[h];[c][h]acrossfade=d={X}:c1=tri:c2=tri[m]")
    else:
        flt = f"[0:a]atrim={a}:{z},asetpts=PTS-STARTPTS,afade=t=in:d=0.3,afade=t=out:st={max(0, L - 1.5):.2f}:d=1.5[m]"
    r = run("ffmpeg", "-y", "-v", "error", "-i", p, "-filter_complex", flt, "-map", "[m]", "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", tmp)
    if r.returncode: print("ERRORE", nome, r.stderr[-300:]); continue
    m = run("ffmpeg", "-i", tmp, "-af", f"loudnorm=I={t}:TP=-1.5:LRA=11:print_format=json", "-f", "null", "-").stderr
    j = json.loads(m[m.rindex("{"):m.rindex("}") + 1])
    ln = (f"loudnorm=I={t}:TP=-1.5:LRA=11:measured_I={j['input_i']}:measured_TP={j['input_tp']}:"
          f"measured_LRA={j['input_lra']}:measured_thresh={j['input_thresh']}:offset={j['target_offset']}:linear=true")
    out = os.path.join(dst, nome + ".ogg")
    r = run("ffmpeg", "-y", "-v", "error", "-i", tmp, "-af", ln, "-ar", "44100", "-c:a", "libvorbis", "-q:a", "6", out)
    print(nome, "<-", f, round(dur(out), 1), "s", "ERRORE" if r.returncode else "ok")
