# Style guide

## Reference analysis

The reference is the Scene launch film (`Scene/Marketing/films/one-theme`) and its research (`research/virality.md`).

Palette: none of the film's own. Each lock screen brings its colors. Type is white, or ink `#141414` on a light theme.
Typography: SF Pro Display Semibold, tracking -0.02 em, two tones (100% and 55%). SF Mono Medium for code.
Composition: the product fills the frame. Words sit bottom left, never over the clock or the password field.
Pacing: a change at least every 2 s. A cut lands on a beat. A held shot always moves (the theme, or the camera).
Motion: cuts snap. Windows step back and forward on a spring. Held shots push in slowly.
Texture: fine grain on every frame, against banding in dark gradients.
Do not copy: Scene's shots, its switcher, its icon wall.

Lessons carried over from Scene's three cuts:

- Every frame shows real content. No placeholder boxes.
- No orbs, particles, floating cards, or glow.
- The screen fills the frame. No small mock in a black void.
- Frame 0 is the poster (X has no custom thumbnail, and autoplays muted).
- The film must read with the sound off: the words are burned in.
- The name shows early.
- Order fast cuts by brightness: no dark-light-dark flashing (WCAG 2.3.1).

## Type

| Use | Face | Size at 1080p | Tone |
|---|---|---|---|
| Line | SF Pro Display Semibold | 68 px | 100% |
| Second line | SF Pro Display Semibold | 68 px | 60% |
| Label (small caps) | SF Mono Medium | 27 to 34 px, tracking 0.08 em | 78% |
| Theme name (small caps) | SF Mono Medium | 30 px, tracking 0.08 em, 88 px above the line's baseline | 100%, over a soft dark patch on a dark theme |
| Code, the agent's prompt | SF Mono Medium | 22 px, 25 px | syntax in the theme's own colors |
| End card | SF Pro Display Semibold | 52 px ("Locky for macOS"), 36 px ("by InsaneArts") | 100%, 62% |

A line is 2 to 6 words. It holds at least 2 beats (1 s). It sits at x = 6%, baseline at 84% of the height (a first
line at 76.5%), left aligned. On a light theme the line is ink. A soft dark scrim (at most 42%) sits under a light
line only. Labels are the film's second voice: a viewer on a phone may miss them, and the film still reads.

The end card's large name is not the film's type: it is the lock screen's own Text widget, typed in the film at 47 s.

## Motion

| Object | Motion | Values |
|---|---|---|
| Cut | hard cut, one frame before the beat | none |
| Cut in the run | lands 3.5% large and settles | outExpo, 0.42 s |
| Held lock screen | slow push in | scale 1.02 to 1.055 (1.07 in the slow section), linear |
| The lock while a password is typed | push toward the field, then back on the last chord | 1.02 to 1.085 over 3.6 s; spring freq 1.1, damping 0.9 back |
| Window step back, the code column | controlled settle | spring, freq 1.25 to 1.5, damping 0.86 to 0.9 |
| Camera to a sheet or a popover | smooth | inOutCubic, 0.4 to 0.9 s |
| Line in | each word rises 16 px and fades in, 0.05 s apart | outExpo, 0.36 s |
| Line out | fade | 0.16 s |
| Pointer | glides to each recorded click in the half second before it; a ring opens on the click | inOutCubic |
| Recorded UI | real time, or 1.2 to 3.2 times as fast; waits are cut | straight lines between [film, clip] points |
| The lock's own animations | as recorded, at their own speed | none |

After each move the viewer knows where to look: one thing moves at a time, and the line names it.

## Banned defaults

Centered text on a gradient. Everything fading in. A logo pop at the end. Particles, lens flares, glow, light leaks.
Gradient text. 3D device mock-ups. Blur behind every title. Keycaps. Stock whooshes on every cut. Any screen, number,
or logo that is not the product's.
