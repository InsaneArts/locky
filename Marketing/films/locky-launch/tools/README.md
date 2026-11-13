# Film tools

The film is a page (`src/film.html`, `src/film.js`, `src/engine.js`) that draws any frame from its time alone. Headless
Chrome renders it and ffmpeg encodes it. Everything on screen is recorded from the real app or drawn by `locky render`.
Run every command from this folder's parent, `Marketing/films/locky-launch`.

## Rebuild the film from the footage

```sh
python3 tools/prepare.py          # footage/ → build/frames/<clip>/, the parts src/clips.json names
python3 tools/lapse.py            # Lookout through the day: 360 frames with `locky render` (about 2 min)
python3 tools/timing.py           # src/events.json and src/transitions.json, measured from the takes
node tools/render.mjs cues        # out/cues.json: every sound's time, from the page
python3 tools/score.py            # out/score.wav: the track and the UI sounds, at -14 LUFS
node tools/render.mjs film --out out/locky-launch-1080p.mp4 --audio out/score.wav      # about 5 min
node tools/render.mjs film --scale 2 --out out/locky-launch-4k.mp4 --audio out/score.wav
node tools/render.mjs sheet 0,8.1,12.4 --name look                                     # stills and a sheet in reviews/
python3 tools/sheet.py out/locky-launch-1080p.mp4 reviews/sheet.jpg 0,8.1,12.4          # a sheet from the video
python3 tools/flash.py out/locky-launch-1080p.mp4                                      # the WCAG 2.3.1 flash check
```

`render.mjs` needs Google Chrome (or `CHROME=<path>`) and ffmpeg with libx264. `score.py` and `music/analyse.py`
need numpy, scipy, soundfile, and librosa.

## Shoot the footage again

The footage is shot in the Atlas helper, a hidden second login, so nothing shows on the owner's desktop.
Locky runs there from `/Applications/Locky.app` with its own config folder (`atlas-work/locky-film/config`), in its
screenshot mode (`--behind`): previews draw although the helper's windows are hidden.

```sh
python3 tools/shoot.py default eventhorizon …                     # footage/lock-<theme>.mkv: a live lock screen, 6 s
python3 tools/sessions.py browse schedule customize               # the Themes window: real clicks, drags, and keys
python3 tools/sessions.py new agent lock                          # one run: build the theme, add the widget, lock
```

- ffmpeg records the helper's screen at its real pixels (2 per point) and crops to the window: 3520 × 1980.
- Every frame carries its wall-clock time, and `sessions.py` logs each action with its wall-clock time and its point
  in the window (`footage/<name>.json`). `timing.py` joins them, so the film draws its pointer in step.
- `look.sh NAME [X Y W H]` saves a look at the helper's screen to `reviews/look/`.
- `sessions.py` takes the positions of the app's controls as they are at a 1760 × 990 window. If the app's layout
  changes, look first, then correct the points.

## The film build

`sessions.py lock` and the three `way-*` takes need a Locky whose lock animation plays over a real screenshot. Locky's
own preview plays it over a drawn stand-in desktop. The film build is the repository at the commit of the shoot, in a
scratch worktree, with one change in `StandInDesktop.picture` (`Sources/Locky/Views/LockTransition.swift`):

```swift
if let path = ProcessInfo.processInfo.environment["LOCKY_DESKTOP"],
   let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
   let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { return image }
```

Build it with `INSTALL=0 Scripts/package_app.sh` in the worktree, and copy the app to
`/Users/Shared/locky-film/Locky.app`, where the helper can run it. It is never installed, and the change is not in
the repository.

## The Rex clip

A second composition of the same studio: `src/rex.html` and `src/rex.js`, 10 s. It is one take of the
locky-rex pack's lock screen, with a tag. The pack is its own repository; `PACK` names its folder for `rex_shoot.py`.

```sh
python3 tools/rex_shoot.py                  # the take, in the helper, with four made-up Rex sessions
python3 tools/prepare.py rexclip
node tools/render.mjs cues --page rex       # out/cues-rex.json
python3 tools/rex_score.py                  # out/score-rex.wav
node tools/render.mjs film --page rex --out out/locky-rex-1080p.mp4 --audio out/score-rex.wav
```

- The take sets the wallpaper's `speed` to 4, so its 36 s loop takes 9 s and each split opens on a beat.
- Rex's terminals do not draw in the helper (its window does), so the clip has no shot of Rex itself.
- The Rex icon in the take is the helper's installed Rex app's own, as the pack shows it.

## Music

`tools/music/make_candidates.py` makes candidates with ElevenLabs Music composition plans (the key comes from the
Keychain item `elevenlabs-api-key`). `tools/music/analyse.py` measures them: tempo, the beats' place against a 0.5 s
grid, and drums and harmony per section. The film is cut to `b-organic`: quiet to 8 s, groove to 24 s, breakdown to
36 s, build to 40 s, groove to 60 s, a last chord at 60 s. Its beats sit 0.045 s after the grid, which `score.py`
takes out.

## Clean up the helper

```sh
atlas close --app Locky
atlas run -- /bin/rm -rf <the helper's home>/atlas-work/locky-film
rm -rf /Users/Shared/locky-film
git worktree remove --force <the scratch worktree>
```
