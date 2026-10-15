# Tokyo Night

The hyprlock look the Linux customizing crowd made famous, in [folke's Tokyo Night](https://github.com/folke/tokyonight.nvim)
colors: hours over minutes in two colors, the date and a greeting under them, and status in the corners.

```lua
locky.setup({ theme = "tokyonight" })
```

## What it shows

- The time, hours in blue over minutes in magenta, in a heavy monospaced face.
- The date in cyan, and a greeting.
- `weather` (top right): the temperature and the sky, from Open-Meteo.
- `battery` (top left), `away` (bottom left: when the screen locked, and wrong passwords since), and the
  keyboard layout (bottom right).

The background is your desktop picture, blurred and tinted ink blue. Without one, the `tokyonight` shader draws a
night city out of focus: blue and magenta glows, and soft lights drifting up.

## Options

```lua
-- Your own city instead of the Mac's location, and no greeting:
locky.theme.extend("tokyonight", function(theme)
  for _, w in ipairs(theme.widgets) do
    if w[1] == "weather" then w.opts.location = "Tokyo" end
  end
end)
```
