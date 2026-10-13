# Gruvbox

A conky desktop in [morhetz's Gruvbox](https://github.com/morhetz/gruvbox) colors: a big clock on the left, and on the
right the sidebar conky fans have kept since the 2000s, each part under a ruled heading.

```lua
locky.setup({ theme = "gruvbox" })
```

## What it shows

- Left: the time in heavy yellow digits, the date in aqua, how much of the day, week, and year has gone, a quote, and
  the password prompt as a shell line (`λ`).
- Right, on a darker band: `system` (CPU and memory bars), `disk`, `network` (speed and a chart of the last
  minutes), `top` (the six busiest programs), `battery`, and `uptime`.

Its own widgets: `gruvbox.panel` (the darker band) and `gruvbox.heading` (a title and a rule, conky style:
`opts.text`, `opts.width`).
