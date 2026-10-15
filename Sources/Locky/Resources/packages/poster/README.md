# Poster

The time as a poster in the International Typographic Style, the Swiss school of the 1950s and 60s: one
grotesque typeface, a strict grid, flush-left ragged-right text, thin rules, and asymmetric layouts built
from big numbers, red, and black.

## What the screen shows

- The hours in Helvetica Neue Condensed Black, 855 points tall (0.95 of the screen's height), in ink, flush
  left on the left margin. The top edge of the screen crops 12% off the digits.
- The minutes in the same face and size in red, flush right on the right margin. The bottom edge crops 10%.
  The red overprints the black: where the minutes cross the hours, the inks multiply into a deep black, and
  the paper's grain shows through the red.
- Top right, on columns 9-12: small Helvetica Neue in ruled blocks. Date (weekday, day, month; AM or PM in
  12-hour locales), week number, user, host, and a numbered list of the herdr agents that need you. The
  list shows up to 4 agents, numbers blocked agents in red, and hides when none need you or herdr is not
  running.
- Bottom left: the weekday running up the left edge in tracked capitals, and the password field, a line in
  columns 1-3.
- On the bottom margin: a ruler across the 12 columns, running off the right edge. A red square steps along
  it, one column every 5 seconds.
- Warm uncoated paper with a fine grain.

All of it sits on one grid laid out for 1440 x 900 points: 72-point margins, twelve 86-point columns, and
24-point gutters. At this size each pair of digits spans 8 columns: the hours columns 1-8, the minutes
columns 5-12.

## Options

Palette roles (`locky.setup({ palette = { ... } })`):

| Role | Default | Used for |
|---|---|---|
| `bg` | `#F1EFE8` | the paper |
| `fg` | `#0A0A0A` | the hours, the text, the rules |
| `accent` | `#DA291C` | the minutes, the seconds square, the password line |
| `muted` | `#7A7872` | labels, the password hint |
| `border`, `danger` | `#0A0A0A`, `#DA291C` | the password line before focus, a wrong password |
| `surface` | `#E6E3DA` | none of the poster's widgets; core widgets you add, such as `analog`, use it |

Widget options (`locky.setup({ widgets = { ["poster.numerals"] = { ... } } })`):

- `poster.numerals`: `font` (`"HelveticaNeue-CondensedBlack"` or `"HelveticaNeue-CondensedBold"`), `size`
  (855), `margin` (72), `crop_top` (0.12), `crop_bottom` (0.10), `hours` and `minutes` (colors), `overprint`
  (true). `part` is `"all"` (both numbers in one widget, placed at the center), `"hours"`, or `"minutes"`.
  The theme places the hours at the top left and the minutes at the bottom right, so both crops hold on
  screens of any shape. Hours follow your locale's 12- or 24-hour setting.
- `poster.info`: `blocks` (any of `"date"`, `"week"`, `"user"`, `"host"`, `"agents"`, in order), `size`
  (14), `rows` (most agents listed, 4).
- `poster.weekday`: `size` (11), `tracking` (3.5), `length` (240), `color`.
- `poster.seconds`: `size` (12), `tick` (7), `bleed` (how far the rule runs past the 12th column, 1200; 0
  stops it at the right margin).

## Notes

- The password field has no placeholder text: on a light background Locky draws placeholders in a light
  system color that does not read. The line and the hint under it mark the field.
- The labels ("Date", "Week", ...) are English.
- Fonts: Helvetica Neue, which ships with macOS.
