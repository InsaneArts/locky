# Observatory

A clear night from a hill with a telescope dome. The stars turn slowly around the pole, the Milky Way crosses the
sky, and one window in the dome is lit. The widgets read like an astronomer's notebook.

```lua
locky.setup({ theme = "observatory" })
```

## What it shows

- The time in a thin face, the date, and the weather (from Open-Meteo) at the top left.
- `moon` (top right): tonight's phase, how much is lit, and the days to the full moon, worked out on the Mac.
- `sun` (left): today's path of the sun from sunrise to sunset, the sun on it by day, and the time to sunrise by
  night.

The `observatory` shader draws the sky. Params: `{ speed, star density }`, both 1 by default; the sky turns once in
about 26 minutes.

```lua
locky.theme.extend("observatory", { background = { params = { 0.5, 1.5 } } })  -- slower, more stars
```
