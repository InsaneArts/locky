# Locky launch film: brief

## Film

One sentence: Your Mac came with one lock screen. Locky has 43, and you can build your own.
Audience: Mac developers who rice their setup (hyprlock, Neovim, Ghostty, r/unixporn, Omarchy), then any Mac user who
likes a beautiful desktop. They watch on X first, muted, in a feed.
Duration: 64 s (32 bars at 120 BPM).
Formats: wide 16:9, 1920×1080 at 60 fps. A tall cut is a later decision.

## Facts (never invented)

Product: Locky, a lock screen for macOS that you build yourself. Themes and widgets are Lua plugins, drawn with
SwiftUI and Metal.

| Claim on screen | Source |
|---|---|
| 43 themes | `locky themes` lists 43 (README still says 28) |
| Live wallpapers, drawn in Metal | README, "drawn entirely in Metal" |
| Lookout follows the real time of day | `packages/lookout/README.md` |
| A theme by day, a theme by night | `docs/settings.md`, `schedule` |
| Drag widgets, add widgets, change the background, colors, font | `docs/create-theme.md` |
| A theme is a Lua file | `docs/create-theme.md`, Export Theme |
| A coding agent can write a widget | `docs/agents.md` |
| A locked Mac's agents keep working, and the lock screen shows which one needs you | macOS does not stop programs when it locks. Locky's `agents` widget (`docs/widgets.md`) and the locky-rex plugin show them. Locky does not keep the Mac awake: `Sources/Locky/System/Power.swift` |
| Unlocks with Touch ID or your password | README, `docs/security.md` |

Copy (proposed by the studio, the owner's call):

1. This is a lock screen.
2. So is this.
3. And this.
4. Your Mac came with one.
5. Locky has 43.
6. Pick one.
7. Lock it your way.
8. Live wallpapers, drawn in Metal.
8a. Lock your Mac. Your agents keep working. / See which one needs you.
9. It follows the real time of day.
10. One theme by day. One by night.
11. Make it yours. / Drag anything. / Add widgets. / Change the sky.
12. Or start from nothing.
13. Every theme is a Lua file.
14. Or ask your coding agent.
15. Then lock.
16. A real lock. Touch ID or your password.
17. Locky for macOS, by InsaneArts.

Labels (small mono capitals): the count in the list (03 / 43), the lock animation's name and "one of 7 lock
animations" (`docs/settings.md`, `lock_animation`), "27 widgets · 6 sizes" (`docs/widgets.md`), the lapse's hour,
and "You watched this lock screen being built."

## Assets

| Asset | Path | Source | Status |
|---|---|---|---|
| Live lock screens, 43 | `footage/lock-<theme>.mkv` | `locky preview`, recorded in the Atlas helper at 3520×1980 | real |
| Themes window, Schedule, Customize, New Theme, the agent's widget | `footage/ui-*.mkv` | Locky.app, real clicks, drags, and typing in the Atlas helper | real |
| Lookout through the day, 360 frames | `build/frames/lapse/` | `locky render`, the shader's own hour parameter (`tools/lapse.py`) | real, see Notes |
| The lock's animation: Tiles, Sweep, Dissolve, Iris | `footage/way-*.mkv`, `footage/lock-in.mkv` | `locky preview --transition`, the film build | real, see Notes |
| The theme built in the film | `config/settings-final.json`, `config/themes/` | written by Locky's editor during `ui-new` and `ui-agent` | real |
| The theme as Lua | `config/themes/launch.lua` | written by hand; `locky render` draws the same screen (mean difference 0.3 of 255) | real |
| The agents' lock screen, 4 s | `footage/rex-clip.mkv`, cut by `tools/rex_timing.py film rex-clip.mkv` | the locky-rex plugin (its own repository), live in the Atlas helper | real, see Notes |
| The agent's widget | `config/plugin/vacation.lua` | written by a coding agent with Locky's skill, from the docs' own prompt; `locky check` passes | real |
| App icon | `assets/icon.png` | `Sources/Locky/Resources/AppIcon.icns` | real |
| Score | `assets/music/b-organic.mp3` | ElevenLabs Music, composition plan (`tools/music/`) | generated for this film |
| Type | SF Pro Display, SF Mono | `/Library/Fonts`, `assets/fonts/` | as in the Scene film |
| Pointer | drawn by the film | at the place and time of each recorded click and drag (`footage/*.json`) | the film's, see Notes |

## Visual rules

Keep: every frame is the real product. The lock screen fills the frame. The app's own windows show the app.
Avoid: grey placeholder boxes, orbs, particles, glow, floating cards, a small screen in a black void, keycaps as the
subject, centered text on a gradient, a logo pop at the end.
Never invent product screens, logos, or metrics.

## Sound

ElevenLabs Music (`music_v2_5`) from a composition plan whose sections land on the film's sections, 120 BPM. Soft UI
sounds on cuts and clicks, mixed under the music, each on a beat-grid time. Normalized to -14 LUFS.

## Engine

A page that draws any frame from its time alone, rendered by headless Chrome and encoded by ffmpeg (the Scene film's
method). It fits because the film is real footage plus type and camera moves, and every frame must be seekable.

## Notes

- Privacy mode is on in every capture: no name, no place, no network address.
- The helper's Locky runs in its screenshot mode (`--behind`), so previews draw while its window is hidden. That
  mode has no location, so the film's config names a city for the weather and sun widgets (the docs' own example).
- Themes animate at their own frame rate (15 to 30 fps). The film does not raise it.
- Lookout's day is `locky render` at each hour, with the shader's hour parameter. The clock widget cannot follow a
  set hour, so the lapse shows the scene alone, as Locky does after 20 s without input. The film's own label shows
  the hour.
- A real lock cannot run in the helper: only its owner can unlock it. The lock's animation is `locky preview
  --transition`, which plays it over a drawn stand-in desktop of grey boxes. The film build of Locky (a scratch
  worktree, never installed, not in the repository) has one change: `$LOCKY_DESKTOP` names a picture that stands
  in instead. The picture is a real frame of the app from the take before. The animation's code is unchanged.
- The pointer is the film's: the helper's clicks are recorded with their place and time, and the film draws an
  arrow there. Every reaction of the app is recorded.
- Waits are cut out of the recorded sessions, and some parts play at 1.2 to 3.2 times their speed.
- The agents' lock screen (26 to 30 s) is the locky-rex plugin, which is not one of Locky's 43 themes; the film's label
  says it is a plugin. Its Rex sessions and their names are made up. Their statuses are real reports through Rex's
  Program Status Protocol, with made-up words. The take in the film is the Rex clip's (`footage/rex-clip.mkv`), so
  Rex's app icon shows in the top pane. `tools/rex_shoot.py film` shoots a take without the icon; the helper was in
  use by other work when this cut was made. The wallpaper's clock runs three times as fast, and the widgets look at
  Rex every second, not every five.
- The film does not say "now you can": a Mac's programs keep running under the macOS lock screen too. Locky adds the view.

## Deliverables

Shot list, contact sheets, one video and one poster, source, asset list, review note.
