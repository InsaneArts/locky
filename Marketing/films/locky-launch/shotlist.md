# Shot list

64 s, 120 BPM: a beat is 0.5 s (30 frames), a bar is 2 s. Every time below is on a beat, and every cut shows one
frame before its beat. The sections follow the score: quiet 0–8, groove 8–24, breakdown 24–36, build 36–40,
groove 40–60, last chord 60–64.

State chain: LOCKED (four looks) → 43 OF THEM → THE APP → LOCK → LIVE → AGENTS → TIME → CUSTOMIZE → BUILD → LOCK → THE NAME.

| Time | Beat | Entry state | Exit state | Words | Purpose |
|---|---|---|---|---|---|
| 0–2 | A1 Hook | Event Horizon, live, full frame (frame 0 is the poster): the theme that looks least like a lock screen | pushed in | This is a lock screen. | Stop the scroll with a claim to doubt |
| 2–4 | A2 | cut: Poster | pushed in | So is this. | The claim grows: from a black hole to Swiss type |
| 4–6 | A3 | cut: Notebook | pushed in | And this. | Range: a ruled page, a sticky note, a coffee ring |
| 6–8 | A4 Problem | cut: Aurora, the theme that looks most like the Mac's own | pushed in | Your Mac came with one. | The problem, said in the score's quiet |
| 8–11.5 | B1 Run | the drop: 7 cuts, one a beat, dark to light: Synthwave, Neon City, Matrix, Phosphor, Tokyo Night, Liquid, Pocket | Pocket | Locky has 43. (with the icon) | The answer, and the name, on the drop |
| 11.5–12 | B2 | the eighth cut is Bauhaus: the Themes window's own preview, filling the frame | same | | Sets up the step back |
| 12–18 | B3 The app | the camera steps back: the preview is inside the real Themes window | the selection has gone down the list, one theme a beat from 13.0 to 17.0, each live, the page in each theme's colors; it stops on Galaxy Sea and holds a second | Pick one. (and a count: 03 / 43 …) | The product, by real use |
| 18–24 | S Lock | on each bar the lock's own animation comes in over the app: Tiles over the walk's last theme (Galaxy Sea), then Sweep (Deep Blue) and Dissolve (Braun), each after a cut to its page an eighth note before | locked | Lock it your way. (label: the style, one of 7 lock animations) | The product's one action, and a feature |
| 24–26 | C1 Live | cut: Snowfall, held | pushed in | Live wallpapers, drawn in Metal. | Let the motion be seen, in the score's quiet |
| 26–30 | C2 Agents | cut: the locky-rex plugin's lock screen, live: glass panes with the agents that report to Rex and the sessions; Terraform's progress grows | at 28.0 Codex starts to need the user: its row turns orange and glides to the top | Lock your Mac. Your agents keep working. / See which one needs you. (label: Plugin · agents, live from Rex) | What a locked Mac still does, and why to look at its lock screen |
| 30–34 | D1 Time | Lookout at the real hour; its widgets go; the day runs to night | night, stars, the lit window | It follows the real time of day. (label: the hour) | The timelapse |
| 34–36 | D2 Schedule | the Themes window; a click opens the Schedule popover | Day: Lookout, Night: Observatory | One theme by day. One by night. | The time story ends in a feature |
| 36–40 | E1 Customize | Aurora's page; a click on Customize…; the clock and the date are dragged left | new layout | Make it yours. / Drag anything. | The turn, in the score's build |
| 40–43.7 | E2 Widgets | the second drop: Add Widget opens; the list scrolls; the calendar changes size twice; a click adds it; it is dragged to its place | calendar on the lock screen | Add widgets. (label: 27 widgets · 6 sizes) | The widget gallery, real |
| 43.7–46 | E3 Sky | Background › Animated; four skies, one a beat: Galaxy Sea, Deep Blue, Synthwave, Sakura | Sakura | Change the sky. | One click changes everything |
| 46–50 | F1 Build | New Theme, eight states, one a beat: blank, a sky, a Text widget, its word, its size, its weight, a line, the line in place | "Launch Day" | Or start from nothing. | A theme from zero in four seconds |
| 50–52 | F2 Lua | the editor's canvas moves right; the theme's Lua file comes in on the left | file beside screen | Every theme is a Lua file. | For the Neovim crowd |
| 52–54 | F3 Agent | the prompt types out; Add Widget shows the widget the agent wrote; a click adds it; it goes to its corner | the theme, finished | Or ask your coding agent. | The newest way in |
| 54–56 | G1 Lock | the editor; the lock's Iris comes in over it | locked: the theme built at 46 s | Then lock. | The payoff of the build |
| 56–60 | G2 | a password is typed (dots); slow push in | field full | A real lock. Touch ID or your password. | Trust |
| 60–64 | H End | the last chord: the camera steps back to the whole lock screen; the icon and the name | held 2 bars | Locky for macOS, by InsaneArts. (label: You watched this lock screen being built.) | The catch: the end card is the lock screen built in the film |

## Continuity

- The password field is in every lock screen. It is the film's fixed point.
- B2 and B3 are one take: the full-frame Bauhaus is the window's preview, seen close.
- F1, F3, G, and H are one run of the app: the clock goes on by a minute or two. The lock comes in over the agent
  session's last frame, in the same minute, and the end card is the same take, still running.
- Each lock in S comes in over a frame of its theme's page shot in the same minute: the page's clock and the lock's agree.
- The list in B3 does not have the theme the film builds at 46 s.
- The walk was shot at a second a step, and the film cuts each wait for a live preview out. Dot Matrix did not draw
  its live preview within its second, so its step is cut out: the count goes from 08 to 10.

## Formats

Wide only. A tall cut follows one object at a time (the clock, the preview, the inspector) and needs its own
composition.

## Beat grid (120 BPM, 0.5 s)

The film's sounds come from one table in `src/film.js` (`window.CUES`), written to `out/cues.json`.

| Time | Cue | Sound |
|---|---|---|
| 0.0 | Aurora | the score's first chord |
| 2, 4, 6 | cuts | a soft knock |
| 8.0 | the run | the score's drop; a click on each of 8 beats |
| 12.0 | step back | air |
| 13.0 … 17.0 | the list moves, 9 beats | ticks |
| 18, 20, 22 | the lock comes in | air, then a low hit |
| 24, 26 | cuts | air; the score's breakdown starts at 24 |
| 28.0 | a program needs the user | two soft notes |
| 31.3 | the day runs | a long rise |
| 33.75 | night | a bell |
| 34.5 | the popover | a pop |
| 36.5 | the editor opens | a tick |
| 37.3, 38.3, 43.17 | drags | air |
| 40.0 | Add Widget | a pop; the score's second drop |
| 41, 41.5, 42 | sizes | ticks |
| 42.5 | the widget lands | a pop |
| 44.25 … 45.75 | four skies | ticks, air |
| 46.1 … 49.6 | eight states | ticks |
| 50.0 | the Lua file | air |
| 52.5, 53, 53.3 | the agent's widget | pops |
| 54.0 | the lock | air, then a low hit |
| 55.4 … 57.5 | 11 keys | a key each |
| 60.0 | end card | the score's last chord |
| 60.7 | the icon | a bell |
