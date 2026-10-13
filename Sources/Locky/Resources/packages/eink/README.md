# E-Ink

The lock screen as an e-paper dashboard, after [TRMNL](https://trmnl.com) and the Kindle dashboards power users build:
black ink on warm white, every panel boxed on a grid.

```lua
locky.setup({ theme = "eink" })
```

## What it shows

- `eink.header`: a black bar with the dashboard's name (`opts.title`), an ordered-dither gradient, and the date.
- `eink.time`: the time in heavy type, the date, and when the screen locked.
- Three days of weather (from wttr.in), this month, a quote, the day, week, month, and year as bars, the moon, and
  the battery, each in its own panel.

Panels are core widgets placed with a `size` and `card = true`: the card fills the size, so they line up on the grid.
