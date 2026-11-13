# Review 2 (draft 3)

A second fresh critic judged `out/locky-launch-draft3.mp4`, without the first review.
Scores: hook 4, readability 3, continuity 3, motion 4, sound sync 3, brand fidelity 4.
Passes: real assets only, type and color consistent, the hook, the last frame, no banned defaults, every cut one
frame before its beat (but 36.500).

## The three largest defects

1. **13.0–14.1: "Pick one." and the count disappear.** The line's tone flips on the step frame, but the page's color
   takes a quarter second to fade over: for 8 to 10 frames the line has almost no contrast.
2. **36.500: the editor opens on old content** (a still picture with "Wednesday, October 14", 10:31) for 8 frames, and
   this cut lands on the beat, not a frame before. The same in small: the Bento preview's still picture for 3 frames
   at 13.0, and the Aurora sky for 9 frames at 46.5 before Galaxy Sea.
3. **46.1–49.6 and 55.4–57.6: UI sounds out of step.** Each tick of the build lands 6 frames after its state change.
   Each key lands 8 to 10 frames before its dot.

## Smaller defects

- 5.0: the Notebook's red margin rule runs through "And this."
- 28–30: Rainy is the darkest shot, has little motion and no line: on a phone the film seems to stop.
- 22–24: the Dissolve shot's label sits 5 px under the Braun clock.
- 53.75–53.95: the pointer crosses "your coding agent."
- The frame cuts off the windows' edges: "hemes" at the left, "Done" at the right.

## What was done

1. **The line in the list walk.** Fixed: it turns from ink to white (and back) with the page's own fade, 0.04 to 0.2 s
   after the step, not on the step. See `reviews/mine/pick.jpg`.
2. **Old content at cuts.** Fixed: the film cuts out the fifth of a second in which the editor, and each theme in the
   list, shows a still picture before its live screen. The build's second state starts on Galaxy Sea. The editor's
   cut is one frame before 36.5. See `reviews/r3-a.png`.
3. **UI sounds.** Fixed: the build's eight states change on their beats and their ticks are on the beats. Each key
   sounds on its dot (0.16 s after the key was sent).

Smaller ones:
- The Notebook's line sits right of the red margin.
- The third live wallpaper is Liquid, not Rainy. Vaporwave takes Liquid's place in the run.
- The Dissolve label sits lower, clear of the Braun clock.
- The pointer fades out before it would cross the agent's line.
- Windows show whole, with their own round corners on black: no "hemes", no cut "Done".
- The changes in the editor (sheet, sizes, widget, skies) show one frame before their beats, as the cuts do.

Two rounds are done (the studio's limit). The final was checked by measurement and by eye, not by a third critic:
`reviews/final-check.txt`.

After the fixes, one more stale picture showed in the final's sheet: Dot Matrix kept its still picture (10:32) for
its whole beat. The walk was shot again at a second a step; Dot Matrix still did not go live, so its step is cut
out. Every theme in the walk now shows its live screen from its first frame.
