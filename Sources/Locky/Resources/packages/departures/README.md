# Departures

An airport departures hall at night: a flip clock over a split-flap board that lists your
[herdr](https://herdr.dev) coding agents like flights. It is the theme for watching agents.

Inspiration: the split-flap boards of 1960s–1990s railway stations and airports, and the classic
two-card flip clock screensaver.

## What it shows

- **Flip clock** (`departures.clock`): two dark cards, hours and minutes, in Helvetica Neue Bold, with a
  split across the middle and hinge notches at both ends. In 12-hour locales the hour card shows AM or PM
  at its top-left.
- **Board** (`departures.board`): the header "DEPARTURES" with an airplane symbol and a count of agents
  per status, then up to 5 rows of FLIGHT / DESTINATION / GATE / REMARKS. Every character sits on its own
  flap.
  - FLIGHT: the agent kind as a two-letter code and the row number (CL 1 for Claude, CX 2 for Codex).
  - DESTINATION: the agent's task title.
  - GATE: the herdr workspace.
  - REMARKS: NEEDS YOU (amber), WORKING (green), or DONE (gray).

  Agents that need you come first, then working agents, then finished ones. Idle agents are not listed
  unless you turn on `idle`. When herdr is not running, the first row reads
  "NO DEPARTURES · HERDR OFFLINE". The board redraws only when what it shows changes.
- **Footer** (`departures.footer`): one small mono line with the battery (left out on Macs without one)
  and the uptime.
- **Password field**: a dark box at the bottom center that turns yellow when focused.

## Palette roles

| Role | Default | Used for |
|---|---|---|
| `bg` | `#0B0B0B` | the background, the card and flap splits |
| `fg` | `#F2F2F2` | letters on the board |
| `muted` | `#9A9A9A` | column labels, DONE, the footer |
| `accent` | `#FFC20E` | the DEPARTURES header, the focused password box |
| `surface` | `#161616` | the flip cards and the password box |
| `border` | `#2A2A2A` | the password box when not focused |
| `warning` | `#FFB000` | NEEDS YOU |
| `success` | `#4CD964` | WORKING |
| `danger` | `#FF453A` | a wrong password |
| `digit` | `#D6D6D6` | the flip clock digits |
| `flap` | `#1C1C1C` | one board flap |
| `idle` | `#5E5E5E` | IDLE, when idle agents are listed |

```lua
locky.setup({ theme = "departures", palette = { accent = "#ffffff", flap = "#202020" } })
```

## Widget options

```lua
locky.setup({
  theme = "departures",
  widgets = {
    ["departures.clock"] = { hour24 = true },          -- leave out to follow the system
    ["departures.board"] = { idle = true, title = "Agents" },
  },
})
```

`departures.clock`: `hour24` (true or false; follows the system when left out), `size` (card side, 360),
`gap` (28), `radius` (30), `digits` (font size, 266), `tracking` (-4), `font` ("Helvetica Neue"), `weight`
("bold"), `color` (role of the digits, "digit"), `card` (role of the cards, "surface"), `split` (role of
the split and notches, "bg"), `split_width` (2).

`departures.board`: `rows` (5; more rows make the board taller), `idle` (false), `tile` (flap size,
`{ 19, 27 }`), `gap` (3), `row_gap` (5), `size` (letter size, 21), `font` ("HelveticaNeue-CondensedBold"), `title`
("Departures"), `offline` and `empty` (the messages for herdr off and for no agents).

`departures.footer`: `size` (11), `color` ("muted"), `tracking` (1.5).
