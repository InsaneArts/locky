# Blueprint

The lock screen as an engineering drawing on Prussian-blue paper, lettered in DIN.

```lua
locky.setup({ theme = "blueprint" })
```

## What it shows

- `blueprint.clock`: a clock drawn as detail A, with center lines, a dimensioned diameter, and the minute hand's angle
  from twelve dimensioned with an arc. Option: `size`.
- `blueprint.titleblock`: the drawing's title block: the title, who drew it, the Mac's name, the date and time, the
  sheet (the day of the year), and the macOS version as the revision. Options: `title`, `width`. Privacy mode shows
  generic names.
- `blueprint.notes`: the sheet's general notes. Options: `notes` (a list of strings), `width`.
- The sun's path, the moon, and the weather.
- The `blueprint` shader draws the paper once: a grid, a double border with zone ticks, the mottling of a print, and
  the creases of a folded sheet. Its colors are the paper and the lines. Parameter 1 sets how many grid cells fit the
  screen's height (default 40).
