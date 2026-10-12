# Station

A homage to the Swiss railway clock that Hans Hilfiker designed for the Swiss federal railways in 1944. The
red second hand with its round disc has the shape of the signal baton that platform staff raise to send a
train off.

The clock behaves like the real one. The second hand sweeps the dial in 58.5 seconds, stops at 12, and waits
for the minute. Then the minute hand jumps, and the second hand sets off again. The hour hand moves with each
jump of the minute hand.

## What the screen shows

- A railway clock, 560 points across, on a warm gray wall lit softly around it. The dial follows the
  railway's own drawing: 48 thin minute bars, 12 thick hour bars, tapered hour and minute hands, and the red
  second hand with its disc near the tip. The case and the hands cast soft shadows.
- The date under the clock, uppercase and tracked: MONDAY 12 OCTOBER, in your language.
- Top left, the computer's name on a black platform sign.
- Under the date, the next "departure": the herdr agent that needs you most, such as
  `NEXT Claude · Fix the login bug · needs you`, with `+2` when more agents wait. Hidden when
  nothing needs you or herdr is not running.
- The password field at the bottom, as a line in the railway red, in Helvetica Neue.

## Options

Palette roles (`locky.setup({ palette = { ... } })`):

| Role | Default | Used for |
|---|---|---|
| `bg` | `#E9E7E2` | the wall |
| `wall_light`, `wall_shade` | `#F1EFEA`, `#DCDAD4` | the light around the clock, the shade in the corners |
| `fg` | `#111111` | the bars, the hands, and the text |
| `muted` | `#6B6965` | secondary text, the password hint |
| `accent` | `#E2001A` | the second hand, the NEXT tag, the password line |
| `surface` | `#FAFAF8` | the dial |
| `case` | `#2B2B2B` | the clock's case |
| `plate`, `plate_text` | `#111111`, `#FFFFFF` | the platform sign |
| `border`, `danger` | `#11111133`, `#E2001A` | the password line before focus, a wrong password |

Widget options (`locky.setup({ widgets = { ["station.clock"] = { ... } } })`):

- `station.clock`: `size` (outer diameter, 560), `seconds` (show the second hand, true), `step` (seconds
  between second-hand moves, 0.2), `sweep` (seconds the second hand takes for one turn, 58.5; 60 gives a
  plain sweep without the stop), `shadow` (true), and the colors `case`, `dial`, `ink`, `second`.
  `part` is `"all"` (the whole clock in one widget) or one of `"dial"`, `"hands"`, `"seconds"`. The theme
  places the three parts at the same spot, so the dial never redraws and only the small second hand redraws
  five times a second. If you move the clock, move all three.
- `station.date`: `format` (`"EEEE d MMMM"`), `size`, `weight`, `tracking`, `color`.
- `station.plate`: `text` (default: the computer's name), `size`, `max_width`.
- `station.departure`: `label` (`"Next"`), `size`, `every` (seconds between herdr checks, 5), `max_width`.

## Notes

- The password field has no placeholder text: on a light background Locky draws placeholders in a light
  system color that does not read. The red line and the hint under it mark the field.
- Fonts: Helvetica Neue, which ships with macOS.
