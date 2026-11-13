#!/usr/bin/env python3
"""Score candidates for the Locky launch film, from ElevenLabs Music (music_v2_5) composition plans.

The key comes from the macOS Keychain (elevenlabs-api-key) and is never printed. Every candidate uses the same
sections, so each lines up with the film the same way. Music time 0 is film time 0. 120 BPM: a bar is 2 s.

  section    seconds   picture
  intro      0-4       the hook: two held lock screens
  drop       4-16      the run of cuts, the step back into the app, the list of 43
  float      16-24     live wallpapers, held
  breakdown  24-30     Lookout through the day, the schedule
  groove     30-42     Customize
  build      42-52     a new theme, Lua, the agent
  lock       52-58     the lock comes in, the password, the unlock
  outro      58-66     the end card (the film ends at 64; the tail is faded)

  python3 make_candidates.py [name ...]     (default: all)
"""
import json, os, subprocess, sys, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "assets", "music")
KEY = subprocess.run(["security", "find-generic-password", "-a", os.environ["USER"], "-s", "elevenlabs-api-key", "-w"],
                     capture_output=True, text=True, check=True).stdout.strip()

NO = ["vocals", "lyrics", "singing", "spoken word", "choir"]
COMMON = ["120 BPM", "instrumental", "polished modern production", "great mix, crisp and wide"]


def plan(genre, key):
    def chunk(text, ms, positive, negative=()):
        return {"text": text, "duration_ms": ms, "context_adherence": "high",
                "positive_styles": positive, "negative_styles": NO + list(negative)}
    return {"chunks": [
        chunk("[Intro]", 4000, genre + COMMON + [key, "starts at once with a warm sustained chord and a deep sub hit on the very first beat",
                                                "a second chord on the third beat", "no drums yet", "a soft pulse", "anticipation"],
              ["drums", "kick", "fade in", "silence", "slow build", "guitar"]),
        chunk("[Drop]", 12000, ["the full groove enters on the first beat", "punchy kick on every beat", "crisp hi-hats",
                                "round sub bass", "the lead melody plays", "confident and bright", "steady four bar phrases"],
              ["dubstep", "trap hi-hat rolls", "guitar", "breakdown"]),
        chunk("[Float]", 8000, ["lighter and airy", "drums thin out to hi-hats and a soft kick", "shimmering arpeggio",
                                "wide warm pads", "a feeling of wonder"],
              ["full drums", "silence", "clap"]),
        chunk("[Breakdown]", 6000, ["breakdown", "no drums", "warm sustained chords", "soft bass", "intimate",
                                    "gentle rising tension toward the end", "a riser into the next section"],
              ["drums", "kick", "hi-hats"]),
        chunk("[Groove]", 12000, ["the full groove returns on the first beat", "punchy kick and clap on the beat",
                                  "the lead melody plays", "confident and bright", "playful"]),
        chunk("[Build]", 10000, ["the groove continues", "the melody develops", "energy rises through the section",
                                 "a short snare build in the last bar", "everything cuts out on the very last beat"],
              ["breakdown", "ambient"]),
        chunk("[Drop]", 6000, ["full energy on the first beat", "one big satisfying downbeat", "punchy drums",
                               "the lead melody returns", "euphoric but tasteful"]),
        chunk("[Outro]", 8000, ["drums stop", "resolves onto one long warm final chord on the first beat",
                                "the chord rings out with a soft reverb tail", "calm ending"],
              ["drums", "abrupt ending", "new melody", "build up"]),
    ]}


CANDIDATES = {
    "a-house": plan(["melodic deep house", "warm electric piano chords", "four on the floor kick", "shuffled crisp hi-hats",
                     "round sub bass", "short glassy pluck lead", "groovy, classy, expensive"], "F minor"),
    "b-organic": plan(["organic house", "felt piano chords", "soft marimba and kalimba plucks", "warm round kick",
                       "light shakers", "deep sub bass", "elegant, human, uplifting"], "D major"),
    "c-lush": plan(["lush melodic electronic", "wide analog synth chords", "crisp punchy drums", "deep round sub bass",
                    "bright bell-like plucked lead melody", "cinematic and sophisticated, product keynote energy"], "A minor"),
}

os.makedirs(OUT, exist_ok=True)
for name in sys.argv[1:] or CANDIDATES:
    body = json.dumps({"composition_plan": CANDIDATES[name], "model_id": "music_v2_5"}).encode()
    req = urllib.request.Request("https://api.elevenlabs.io/v1/music?output_format=mp3_48000_320", data=body, method="POST",
                                 headers={"xi-api-key": KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            data = r.read()
            song = r.headers.get("song-id") or r.headers.get("x-song-id") or ""
    except urllib.error.HTTPError as e:
        print(name, "failed:", e.code, e.read()[:600].decode(errors="replace"))
        continue
    path = os.path.join(OUT, f"{name}.mp3")
    open(path, "wb").write(data)
    json.dump({"plan": CANDIDATES[name], "song_id": song}, open(os.path.join(OUT, f"{name}.json"), "w"), indent=1)
    print(name, "->", os.path.relpath(path), len(data), "bytes", song)
