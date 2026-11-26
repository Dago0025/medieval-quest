"""Compone gli effetti di Medieval Quest dai pacchetti CC0 di Kenney (sfx_cc0/) con ffmpeg.
Uso: python3 componi_sfx.py <cartella_uscita>"""
import subprocess, sys, os, json
B = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sfx_cc0")
P = {"rpg": "rpg-audio/Audio", "imp": "impact-sounds/Audio", "cas": "casino-audio/Audio"}
def f(k, n): return os.path.join(B, P[k], n + ".ogg")
# (sorgente, ritardo s, guadagno dB, semitoni)
R = {
 "SELECT":        [(f("imp","impactWood_light_002"), 0, 0, 2)],
 "DESELECT":      [(f("imp","impactWood_light_004"), 0, -2, -4)],
 "PICKUP":        [(f("cas","dice-grab-1"), 0, -2, -3)],
 "drop_friendly": [(f("imp","impactWood_medium_001"), 0, 0, 0)],
 "drop_hostile":  [(f("imp","impactWood_heavy_000"), 0, 0, 0), (f("imp","impactSoft_heavy_000"), 0.05, -3, -5), (f("imp","impactSoft_heavy_002"), 0.30, -5, -5), (f("imp","impactSoft_heavy_004"), 0.52, -7, -6)],
 "merge_armies":  [(f("rpg","clothBelt"), 0, -3, 0), (f("rpg","metalClick"), 0.12, -4, -2), (f("rpg","footstep00"), 0.35, -6, 0), (f("rpg","footstep01"), 0.62, -7, 0), (f("imp","impactMetal_light_003"), 0.5, -8, -3)],
 "PARCH_UP":      [(f("rpg","bookFlip1"), 0, 0, -1)],
 "parch_down":    [(f("rpg","bookFlip3"), 0, 0, -2), (f("rpg","bookClose"), 0.12, -3, 0)],
 "build":         [(f("imp","impactMining_000"), 0, -2, 0), (f("rpg","chop"), 0.45, -3, 0), (f("imp","impactMining_002"), 0.9, -3, 1), (f("imp","impactMining_004"), 1.5, -4, -1)],
 "Money":         [(f("rpg","handleCoins"), 0, 0, 0), (f("rpg","handleCoins2"), 0.55, -4, 0)],
 "SAVED":         [(f("rpg","bookPlace2"), 0, -2, -3), (f("imp","impactSoft_medium_001"), 0.02, -1, -6)],
}
# picco finale in dBFS, ricalcato sui suoni dell'originale
T = {"SELECT": -9, "DESELECT": -13, "PICKUP": -16, "drop_friendly": -11, "drop_hostile": -4, "merge_armies": -8,
     "PARCH_UP": -16, "parch_down": -16, "build": -2, "Money": -2, "SAVED": -2}
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
for nome, parti in R.items():
    cmd = ["ffmpeg", "-y", "-v", "error"]
    flt = []
    for i, (src, d, g, st) in enumerate(parti):
        cmd += ["-i", src]
        r = 2 ** (st / 12)
        flt.append(f"[{i}:a]aformat=sample_rates=44100:channel_layouts=stereo,asetrate={int(44100*r)},aresample=44100,volume={g}dB,adelay={int(d*1000)}|{int(d*1000)}[a{i}]")
    mix = "".join(f"[a{i}]" for i in range(len(parti)))
    flt.append(f"{mix}amix=inputs={len(parti)}:normalize=0:duration=longest,areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse[m]")
    tmp = os.path.join("/tmp", nome + "_tmp.wav")
    subprocess.run(cmd + ["-filter_complex", ";".join(flt), "-map", "[m]", "-c:a", "pcm_s16le", tmp], check=True)
    # normalizza il picco al livello dell'originale
    vol = subprocess.run(["ffmpeg", "-i", tmp, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True).stderr
    peak = float([l for l in vol.splitlines() if "max_volume" in l][0].split(":")[1].split()[0])
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", tmp, "-af", f"volume={T.get(nome, -3)-peak}dB", "-c:a", "pcm_s16le", os.path.join(out, nome + ".wav")], check=True)
    try: os.remove(tmp)
    except OSError: pass
    print(nome, "ok")
