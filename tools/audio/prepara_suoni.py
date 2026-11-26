"""Fanfare e segnali di Medieval Quest da Freesound (tutti CC0).
Uso: python3 prepara_suoni.py <sorgenti> <assets/audio/suoni>
Ogni voce: parti (file, inizio, durata, ritardo, dB); poi filtro morbido sugli acuti, dissolvenza e volume medio come l'originale."""
import subprocess, sys, os, re
src, dst = sys.argv[1], sys.argv[2]
# nome: ([(file, da, durata, ritardo, dB)], dissolvenza finale, volume medio dB, ammorbidisci acuti)
S = {
 "Euro Fanfare 1": ([("fs_350428.mp3", 0, 7.6, 0, 0)], 0.8, -24, True),     # Trumpet Fanfare, bevibeldesign
 "Euro Fanfare 2": ([("fs_423293.mp3", 0, 10.6, 0, 0)], 1.0, -24, True),    # FanFare.wav, DylanTheFish
 "Euro Fanfare 3": ([("fs_669298.mp3", 0, 6.0, 0, 0)], 1.2, -25, True),     # Trumpet call, Jorgemaca
 "Euro Fanfare 4": ([("fs_456966.mp3", 0, 4.4, 0, 0)], 1.0, -24, True),     # Success Fanfare Trumpets, FunWithSound
 "endofseason":    ([("fs_73678.mp3", 0, 7.9, 0, 0), ("fs_392180.mp3", 0, 4.3, 2.2, -5)], 1.5, -26, False),  # TollBell daytripper + Battle_horn_1 kirmm
 "NEGATIVE":       ([("fs_539956.mp3", 0, 1.3, 0, 0)], 0.35, -22, False),   # war horn, adharca
}
def run(*a): return subprocess.run(list(a), capture_output=True, text=True)
os.makedirs(dst, exist_ok=True)
for nome, (parti, fade, media, morbido) in S.items():
    cmd = ["ffmpeg", "-y", "-v", "error"]; flt = []
    for i, (f, da, d, rit, g) in enumerate(parti):
        cmd += ["-i", os.path.join(src, f)]
        flt.append(f"[{i}:a]aformat=sample_rates=44100:channel_layouts=stereo,atrim={da}:{da + d},asetpts=PTS-STARTPTS,"
                   f"afade=t=in:d=0.01,volume={g}dB,adelay={int(rit * 1000)}|{int(rit * 1000)}[a{i}]")
    mix = "".join(f"[a{i}]" for i in range(len(parti)))
    eq = ",highshelf=f=5000:g=-5,lowpass=f=10000" if morbido else ""
    flt.append(f"{mix}amix=inputs={len(parti)}:normalize=0:duration=longest{eq}[m0]")
    tmp = "/tmp/_s.wav"
    r = run(*cmd, "-filter_complex", ";".join(flt), "-map", "[m0]", "-c:a", "pcm_s16le", tmp)
    if r.returncode: print("ERRORE", nome, r.stderr[-300:]); continue
    L = float(run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", tmp).stdout)
    o = run("ffmpeg", "-i", tmp, "-af", "volumedetect", "-f", "null", "-").stderr
    mean = float(re.findall(r"mean_volume: (-?[\d.]+)", o)[0]); mx = float(re.findall(r"max_volume: (-?[\d.]+)", o)[0])
    g = min(media - mean, -3 - mx)
    out = os.path.join(dst, nome + ".wav")
    r = run("ffmpeg", "-y", "-v", "error", "-i", tmp, "-af", f"afade=t=out:st={max(0, L - fade):.2f}:d={fade},volume={g:.2f}dB", "-c:a", "pcm_s16le", out)
    print(nome, round(L, 2), "s", f"guadagno {g:.1f} dB", "ERRORE" if r.returncode else "ok")
