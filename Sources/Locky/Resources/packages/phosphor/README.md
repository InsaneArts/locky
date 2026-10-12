# Phosphor

An amber CRT terminal, after [cool-retro-term](https://github.com/Swordfish90/cool-retro-term). The lock screen
is a shell session on the curved glass of an old amber monitor, and the password prompt is its next line.

```lua
locky.setup({ theme = "phosphor" })
```

## What it shows

From the top-left, as a terminal transcript:

- `Last login: Mon Oct 12 16:16 on console`: when the screen locked.
- `clock`: the time in a block font, drawn as lines of `█`, with the date under it. 12- or 24-hour, as your
  Mac is set.
- `neofetch`: a padlock logo next to `user@host`, the macOS version, the Mac's model and chip, uptime,
  battery, CPU use, memory, and the keyboard layout. A Mac without a battery skips that line.
- `herdr status`: the [herdr](https://herdr.dev) agents that need you or are working, in a table of
  STATUS, TITLE, and WORKSPACE. An agent that needs you shows in reverse video; idle agents are only
  counted. `herdr: offline` when herdr is not running.
- The password prompt: `you@host ~ % unlock`. After a wrong password, `Sorry, try again.` appears under it.

Behind it all, the shader `phosphor` draws the tube: a warm center fading to the edges, a curved screen in a
dark bezel, faint static, and a soft bright band that rolls down the screen every 6 seconds. The overlay
`phosphor-overlay` adds scanlines, a vignette, and a slight flicker over the text too, and the text glows in
its own color.

## Options

Palette roles (`locky.setup({ palette = { ... } })`): `fg` (the phosphor: text and the clock), `bright`
(labels and headers), `muted` (secondary text), `accent` (the prompt), `bg` (text in reverse video),
`danger` (a low battery, a wrong password). For a green screen:

```lua
locky.setup({ theme = "phosphor", palette = { fg = "#33ff66", accent = "#33ff66", bright = "#99ffb0", muted = "#1f9e40" } })
```

The shaders take the tube's colors from the theme's `background.colors` (glass center, glass edge, phosphor),
so a green screen also wants `locky.theme.extend("phosphor", { background = { colors = { "#020d04", "#000502", "fg" } } })`.

Widget options (`locky.setup({ widgets = { ["phosphor.session"] = { ... } } })`):

| Option | Default | |
|---|---|---|
| `clock`, `fetch`, `herdr` | `true` | `false` leaves that command out of the session |
| `logo` | `true` | `false` drops the padlock next to neofetch's lines |
| `rows` | `5` | most agents listed; idle ones are only counted |
| `every` | `5` | seconds between herdr checks |
| `clock_size` | `28` | the block clock's character size |
| `glow` | `3` | the text's glow radius; the clock glows 2.5 times as much |
| `low` | `20` | battery percent at or below which the battery line turns `danger` |

The session ends right above the password prompt and grows upward. Its box in the theme is tall enough for
the default `rows`; if you raise `rows` or `clock_size`, raise the box and the prompt with it.

Shader parameters: `background.params` = { seconds per band pass (6), band strength (1), static strength (1),
curvature (1) }; `overlay.params` = { scanlines across the screen (300), scanline strength (0.16), vignette
(0.4), flicker (1) }. Set `overlay = false` with `locky.theme.extend` for a clean screen.
