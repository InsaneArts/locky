#!/usr/bin/env python3
"""Measure each candidate against the film's grid: tempo, beat phase, drum and harmony energy per section, loudness."""
import subprocess, sys, json, numpy as np, librosa

BEAT = 0.5
import os
SECTIONS = [("intro",0,4),("drop",4,16),("float",16,24),("breakdown",24,30),("groove",30,42),("build",42,52),("lock",52,58),("outro",58,66)]

def lufs(path):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-af", "ebur128=peak=true", "-f", "null", "-"],
                       capture_output=True, text=True).stderr
    tail = r[r.rfind("Summary:"):]
    get = lambda key: float(tail.split(key)[1].split()[0])
    return get("I:"), get("Peak:")

for path in sys.argv[1:]:
    y, sr = librosa.load(path, sr=22050, mono=True)
    dur = len(y) / sr
    tempo, beats = librosa.beat.beat_track(y=y, sr=sr, start_bpm=120, units="time", tightness=400)
    tempo = float(np.atleast_1d(tempo)[0])
    ivals = np.diff(beats)
    onset = librosa.onset.onset_strength(y=y, sr=sr, hop_length=256)
    times = librosa.times_like(onset, sr=sr, hop_length=256)
    best, phase = -1, 0
    for p in np.arange(0, BEAT, 0.005):
        idx = np.clip(np.searchsorted(times, np.arange(p, times[-1], BEAT)), 0, len(onset) - 1)
        s = onset[idx].mean()
        if s > best: best, phase = s, p
    H, P = librosa.effects.hpss(y)
    def db(x, a, b):
        seg = x[int(a * sr):int(b * sr)]
        return 10 * np.log10(np.mean(seg ** 2) + 1e-12)
    I, peak = lufs(path)
    print(f"\n== {path.split('/')[-1]}  {dur:.2f} s  tempo {tempo:.2f} BPM  beat intervals {ivals.mean():.3f}±{ivals.std():.3f} s"
          f"  grid phase {phase:.3f} s (fit {best:.2f}, mean {onset.mean():.2f})  {I:.1f} LUFS  peak {peak:.1f} dBFS")
    print("  first beats:", " ".join(f"{b:.2f}" for b in beats[:6]))
    for name, a, b in SECTIONS:
        print(f"  {name:10s} {a:4.0f}-{b:<4.0f} drums {db(P, a, b):6.1f} dB   harmony {db(H, a, b):6.1f} dB")
    per = [db(y, s, s + 0.5) for s in np.arange(0, dur, 0.5)]
    print("  dB per half second:", " ".join(f"{v:.0f}" for v in per))
    # the strongest onsets near each section boundary: does the music change where the film cuts?
    for name, a, _ in SECTIONS[1:]:
        w = (times > a - 0.4) & (times < a + 0.4)
        i = np.argmax(np.where(w, onset, 0))
        print(f"  boundary {a:>4.1f} s: strongest onset at {times[i]:.3f} s, strength {onset[i] / onset.mean():.1f}x mean")
