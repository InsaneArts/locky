# Review 1 (draft 2)

A fresh critic judged `out/locky-launch-draft2.mp4` from contact sheets and its own stills, against `brief.md` and
`style-guide.md`. Scores: hook 3, readability 3, continuity 2, motion 3, sound sync 3, brand fidelity 3.

## The three largest defects

1. **Lock transitions, 18.0–18.4 and 54.0–54.3.** In stills the lock's way in looks like a glitch, then a blank
   screen: on a dark page and a dark theme the screen goes near black before the clock fades in.
2. **The agent shot, 52.4.** "coding agent." sits on the white sheet. The agent's widget is in the list while the
   prompt is still typing: the effect shows before its cause.
3. **The list walk and the three locks, 12.9–22.0.** Each list step first flashes a stale thumbnail. The walk ends on
   Galaxy Sea, then the film cuts back up the list to Cyberdeck HUD. The cuts to the app before each lock are off
   the beat.

## Smaller defects

- 0–2: Aurora is the most macOS-like theme: "This is a lock screen." is a claim nobody doubts. The surprise starts at 3 s.
- 7.0: "Your Mac came with one." reads on into Station's "FRIDAY 13 NOVEMBER".
- 18.75, 20.9: the line sits on the theme's own text.
- 36.6: the editor opens on a soft thumbnail with a stale date.
- 59.5: the push crops the date and the widget.
- 60–64: the name is 56 px, not the style guide's 150. "Built 14 seconds ago" contradicts the clock (11:01, 11:03).
- Labels are 4 to 6 px at phone size.
- Sync: from 8 s the score's beats land 21 ms before the grid. The run's cuts land on the beat frame, not one frame
  before. The list steps come 5 to 6 frames early; the sky changes 2 to 3 frames late.

## What was done

1. **Lock transitions.** Not changed as an effect: they are the product's own animation, recorded. Changed what they
   play over: Tiles over Galaxy Sea, Sweep over Deep Blue, Dissolve over Braun, where the way in reads. See
   `reviews/r2-ways.png`.
2. **The agent shot.** Fixed: the prompt types out over the editor first, then the sheet shows the widget. The line
   is two lines and the sheet sits right of it. See `reviews/r2-c.png`, 52.3 to 53.9.
3. **The list walk and the locks.** Fixed: each move lands a frame before its beat, and the wait for the live preview
   plays fast (the still picture shows for about 4 frames). The walk stops on Galaxy Sea, and the first lock comes in
   over it with no cut. The other two cut to their page an eighth note before the bar. See `reviews/r2-a.png`.

Smaller ones:
- The hook now opens on Event Horizon, then Poster, Notebook, and Aurora for "Your Mac came with one." Station is out.
- The editor's still picture shows for 7 frames, not 24.
- The push on the lock stops at 1.085, where the date and the widget are whole.
- The style guide now gives the end card's real sizes. The label reads "You watched this lock screen being built."
- Labels are 27 to 34 px. They stay the film's second voice.
- Sync: the score starts 21 ms later; every run of cuts lands one frame before its beat; the sky and size changes
  land a frame before theirs.
- Found while fixing: each lock's page and its lock were shot minutes apart, so their clocks differed. Every pair is
  now shot in the same minute. The list showed the theme the film builds later; it is now shot from a clean config.
