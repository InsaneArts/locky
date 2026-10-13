# Broadsheet

The lock screen as a newspaper's front page, set in Bodoni and Baskerville on newsprint.

```lua
locky.setup({ theme = "broadsheet" })
```

## What it shows

- `broadsheet.masthead`: the paper's name between rules, and the dateline: the volume in Roman numerals (years since
  1970), the number (the day of the year), the date, and the edition. `opts.title` names your paper.
- The lead headline: a quote from the `quote` widget, changing every hour.
- Weather: today's weather from wttr.in, with wind, humidity, sunrise, and sunset.
- The Hour: the time in Bodoni, in words, and the date.
- `broadsheet.markets`: the Mac's numbers as a market table, CPU, memory, disk, and battery, each with ▲ or ▼ and its
  change since the last reading, every 30 seconds.
- `broadsheet.almanac`: sunrise, sunset, the moon, and the days left in the year, at the foot of the page.
