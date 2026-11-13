#!/usr/bin/env python3
"""Builds the thread's clips and stills (src/thread.js) into out/thread/, in the order of THREAD.md.

Each clip gets a part of the film's sound. A part of the film itself takes the same part of out/score.wav. A new
clip takes the track alone (no film sounds), from a place where its cuts meet the track's bars, at the level the
track has in the film's mix.

  python3 tools/thread_build.py [clip ...]      # all of them without names
"""
import json, os, shutil, subprocess, sys
import numpy as np
import soundfile as sf

FILM = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(FILM, "out", "thread")
MUSIC = os.path.join(FILM, "assets", "music", "b-organic.mp3")
SCORE = os.path.join(FILM, "out", "score.wav")
PHASE = 0.024       # tools/score.py: the track's beats sit this far after the film's
SR = 48000

# number, clip, seconds, sound ("music" or "score"), where the sound starts in the film's time, fade out
CLIPS = [
    (1, "themes", 24.5, "music", 38.5, 1.6),       # the drop on the fourth theme, the last chord on the end card
    (2, "live", 16, "music", 24, 1.2),             # the breakdown, then the build
    (3, "animations", 18.5, "music", 40, 0.8),     # the groove: a lock on each bar from the third
    (4, "customize", 10, "score", 36, 0.4),
    (5, "time", 6, "score", 26, 0.4),
    (6, "touchid", 8, "music", 0, 0.8),            # the quiet opening: the cut on its second bar
    (7, "photo", 8, "music", 28, 0.8),
    (8, "build", 8, "score", 46, 0.4),
    (9, "plugins", 9.5, "music", 26, 0.8),         # the cut to the lock on a bar
    (10, "settings", 10, "music", 24, 0.8),
    (11, "agents", 10, "score", 54, 0),            # to the film's end: its own fade
]
STILLS = [(12, "privacy"), (13, "safety")]


def run(*args):
    subprocess.run(args, check=True, cwd=FILM)


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(SR), "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).reshape(-1, 2).astype(np.float64)


names = sys.argv[1:]
os.makedirs(os.path.join(OUT, "audio"), exist_ok=True)
score, music = decode(SCORE), decode(MUSIC)[int(PHASE * SR):]
# The track's level in the film's mix: the mix is the track times one gain, plus the film's own sounds.
n = min(len(score), len(music))
gain = float((score[:n] * music[:n]).sum() / (music[:n] ** 2).sum())
print(f"the track's gain in the mix: {20 * np.log10(gain):.1f} dB")

for number, clip, seconds, sound, start, fade in CLIPS:
    if names and clip not in names:
        continue
    a, length = int(start * SR), int(seconds * SR)
    part = (score[a:a + length] if sound == "score" else music[a:a + length] * gain).copy()
    part = np.concatenate([part, np.zeros((length - len(part), 2))])
    if start:
        k = int(0.012 * SR)
        part[:k] *= np.linspace(0, 1, k)[:, None]
    if fade:
        k = int(fade * SR)
        part[-k:] *= np.linspace(1, 0, k)[:, None] ** 2
    wav = os.path.join(OUT, "audio", f"{clip}.wav")
    sf.write(wav, part.astype(np.float32), SR, subtype="PCM_24")
    out = os.path.join(OUT, f"{number:02d}-{clip}.mp4")
    run("node", "tools/render.mjs", "film", "--page", "thread", "--clip", clip, "--workers", "8", "--out", out, "--audio", wav)
    probe = json.loads(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height,r_frame_rate:format=duration,size",
                                       "-of", "json", out], capture_output=True, text=True).stdout)
    video, audio = probe["streams"][0], probe["streams"][1]
    took = float(probe["format"]["duration"])
    assert abs(took - seconds) < 0.05, (clip, took, seconds)
    print(f"{number:02d}-{clip}.mp4: {video['width']}x{video['height']} {video['r_frame_rate']} {took:.2f} s, {audio['codec_name']}, "
          f"{int(probe['format']['size']) / 1e6:.1f} MB", flush=True)

for number, clip in STILLS:
    if names and clip not in names:
        continue
    # A still is the clip's first frame, at 3840 x 2160.
    run("node", "tools/render.mjs", "sheet", "0", "--page", "thread", "--clip", clip, "--name", f"thread-{clip}", "--scale", "2")
    shutil.copy(os.path.join(FILM, "reviews", f"thread-{clip}", "t000.00.png"), os.path.join(OUT, f"{number:02d}-{clip}.png"))
    print(f"{number:02d}-{clip}.png", flush=True)
