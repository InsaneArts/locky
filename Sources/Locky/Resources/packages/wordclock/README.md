# Word Clock

The time spelled out in words on a letter grid, after the QLOCKTWO word clock: a matte black face,
110 letters, and only the ones that tell the time lit.

**English only.** The grid and the phrases are English, whatever your system language is. The date line
under the grid uses your system's names for the weekday and month.

## What it shows

- **Grid** (`wordclock.grid`): 11 columns by 10 rows in the classic English layout:

  ```
  I T L I S A S A M P M
  A C Q U A R T E R D C
  T W E N T Y F I V E X
  H A L F S T E N F T O
  P A S T E R U N I N E
  O N E S I X T H R E E
  F O U R F I V E T W O
  E I G H T E L E V E N
  S E V E N T W E L V E
  T E N S E O C L O C K
  ```

  It lights "IT IS", the five-minute phrase, and the hour: "IT IS TWENTY FIVE TO THREE",
  "IT IS A QUARTER PAST NINE", "IT IS TWELVE O'CLOCK". Like the original it shows the last five-minute
  step that has passed, and from :35 it counts down to the next hour. The four dots in the corners count
  the minutes after the step, clockwise from the top-left: at 9:47 the face reads "IT IS A QUARTER TO TEN"
  with two dots lit. Lit letters glow softly; unlit letters stay faintly visible. The grid redraws once a
  minute, on the minute.
- **Date** (`wordclock.date`): a small tracked line on the bottom edge of the face, between the two lower
  dots.
- **Password field**: "minimal". Nothing shows until you type; just start typing your password.

## Palette roles

Recolor the face with the palette. Warm lit letters:

```lua
locky.setup({ theme = "wordclock", palette = { accent = "#FFD9A0" } })
```

A white front with dark letters (turn the glow off on light faces):

```lua
locky.setup({
  theme = "wordclock",
  palette = { bg = "#ECEAE4", fg = "#000000", accent = "#111111", muted = "#00000066" },
  widgets = { ["wordclock.grid"] = { glow = false } },
})
```

| Role | Default | Used for |
|---|---|---|
| `bg` | `#0D0D0D` | the face |
| `fg` | `#FFFFFF` | unlit letters and dots (drawn at 10%), the typed password |
| `accent` | `#FFFFFF` | lit letters, their glow, lit dots |
| `muted` | `#FFFFFF59` | the date and the password hint |
| `danger` | `#FF3B30` | a wrong password |

## Widget options

```lua
locky.setup({ theme = "wordclock", widgets = { ["wordclock.grid"] = { dim = 0.14, glow = { 4, 16 } } } })
```

`wordclock.grid`: `cell` (letter square, 62), `size` (letter size, 38), `font` ("Avenir Next"), `weight`
("semibold"), `lit` (role of lit letters, "accent"), `unlit` (role of unlit letters, "fg"), `dim`
(opacity of unlit letters, 0.1), `glow` (inner and outer glow radii, `{ 6, 22 }`; false for none), `glow_opacity`
(`{ 0.55, 0.4 }`), `dot` (corner dot size, 7), `dot_inset` (from the grid's corner to a dot, 22).

`wordclock.date`: `format` ("EEEE d MMMM"), `size` (13), `tracking` (4.5), `font` ("Avenir Next"),
`weight` ("semibold"), `color` ("muted").
