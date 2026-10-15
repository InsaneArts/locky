# Create a theme

You can make a theme in the Themes window without code, or write it in Lua. Both give you a `.lua` file in
`~/.config/locky/themes/` that you can share.

## In the Themes window

1. Choose **File › New Theme…** (⌘N), or click + in the Themes window's toolbar. The Settings window has
   New Theme… too. Locky makes a theme named "Untitled Theme" and opens it in Customize. It starts dark, with
   the date and the clock in the top third and the password field at the bottom.
2. Type a name in **Name**, at the top of the inspector. The file keeps its first name, such as
   `untitled-theme.lua`, so settings that name the theme still work.
3. Choose a **Background**:
   - **Animated** shows a picture of each animated background that Locky's themes use, such as Aurora,
     Snowfall, and Rainy. Click one to use it. Its colors come with it. **Dim** darkens it, so text stays
     easy to read.
   - **Desktop Picture**, **Image**, **Video**, **Color**, and **Gradient** work as in any theme.
     **Original** goes back to the theme's own background.
4. Choose **Colors**: **Text** (the palette's `fg`), **Secondary Text** (`muted`), **Accent** (`accent`), and
   **Cards**, the fill of the cards that widgets sit on. A color that had transparency, such as Secondary
   Text, keeps it.
5. Choose a **Font**: a family (System, or any font on your Mac), a weight, and for the system font a design
   (Default, Rounded, Serif, or Monospaced). Text whose widget sets its own weight or design keeps it. The
   clock does: select it to change its weight.
6. Add **Widgets** with + in the toolbar (or Edit › Add Widget…). **Text** shows your own words: select it,
   type the words, and choose a size, a weight, an alignment, and a color. Drag widgets on the canvas, and
   select one to change its options.
7. Select **Password Field** to move it.

Each change saves at once, and Edit › Undo takes it back. Reset next to Colors or Font takes that section back
to the theme's own. Done returns to the themes. A theme you leave without changes stays in the gallery; Move to
Trash removes it.

All of this works for every theme, Locky's own too. The changes are a layer in `settings.json` (`themes.<id>`,
see [themes.md](themes.md#make-and-share-themes-in-the-window)) over the theme file. Export Theme… and
Duplicate Theme… write them into a file.

### Share it

**Export Theme…** (in Customize's More menu and the File menu) saves the theme with all your changes as one
`.lua` file: the background, colors, font, widgets, and the password field's place. On another Mac, **File ›
Import Theme…** adds it. Locky imports only files in the shape Export Theme writes, and only with widgets that
come with Locky. See [themes.md](themes.md#make-and-share-themes-in-the-window).

## In Lua

A theme is a Lua file that returns a table. Put it in `~/.config/locky/themes/<id>.lua`:

```lua
-- ~/.config/locky/themes/harbor.lua
return {
  name = "Harbor",
  description = "A calm blue evening.",
  palette = { bg = "#0e1b2c", fg = "#eef3f8", muted = "#eef3f899", accent = "#ffb347" },
  font = { family = "Avenir Next", weight = "medium" },
  background = { gradient = { "#0e1b2c", "#24476b" }, angle = 180, noise = 0.03 },
  card = { style = "glass", radius = 18 },
  auth = { style = "pill", anchor = "bottom", offset = { 0, -60 } },
  widgets = {
    { "date", anchor = "top", offset = { 0, 110 }, opts = { size = 22 } },
    { "clock", anchor = "top", offset = { 0, 130 }, opts = { size = 140, weight = "medium" } },
    { "text", anchor = "center", offset = { 0, 80 }, opts = { text = "Gone fishing", size = "large", color = "accent" } },
    { "battery", family = "circular", anchor = "bottom-left", offset = { 40, -40 } },
  },
}
```

The Themes window lists it at once. To check it:

```
locky check --theme harbor        lists every error
locky preview --theme harbor      the lock screen in a window
Scripts/snapshot.sh harbor out.png   (in the source tree) a PNG of it
```

[themes.md](themes.md) has every field: placement, Apple's widget families, the backgrounds, overlays, the
password field's styles, and how to write a Metal shader. [widgets.md](widgets.md) lists the widgets, and
[views.md](views.md) the views your own widgets can draw.

An animated background is a shader: `background = { shader = "snowfall" }` uses one of Locky's, by the name of
its file in a `shaders/` folder. A shader of your own goes in `~/.config/locky/shaders/<name>.metal`.

## Package and share

A theme with its own shader, images, or widgets is a package: a folder, or a git repository, laid out like the
config folder.

```
locky-harbor/
  themes/harbor.lua         -- the theme
  shaders/harbor.metal      -- its background, if it has its own
  plugin/harbor.lua         -- its own widgets, if any (locky.widget.define)
  assets/                   -- images, if any
  README.md
```

Push it to GitHub. Others add it in Settings › Plugins, or in `init.lua`, and then choose it in the Themes
window:

```lua
locky.pack.add({ "you/locky-harbor" })
```

and run `locky pack sync`. [plugins.md](plugins.md#a-package) explains packages, versions, and the lockfile.
