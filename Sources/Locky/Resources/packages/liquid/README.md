# Liquid

Color poured into color, folding over itself like silk. The flow never repeats, and the folds catch a soft light.
The lock screen is laid out like a phone's: the date over a big rounded clock, and a row of glass widgets.

```lua
locky.setup({ theme = "liquid" })
```

## What it shows

- The date, the time, and glass widgets for the weather, how much of the day and year has gone, and this month.
- The `liquid` shader draws the flow. Its colors are four paints, deepest to brightest, and the sheen on the folds.
  Parameters: how fast it flows (1), how large the folds are (1), and how much sheen (1).
