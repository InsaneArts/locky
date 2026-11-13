# The thread under the launch film

Drafts. Approve or change them before anything is posted. One reply a feature, in this order. Each file is in
`out/thread/`. Every clip is 1920 × 1080 at 60 fps with its words burned in, so it reads with the sound off.
`tools/thread_build.py` makes 1 to 13 again; 14 and 15 are copies of the Rex clip and the film's end card.

| # | File | Kind | Length |
|---|---|---|---|
| 1 | `01-themes.mp4` | video | 24.5 s |
| 2 | `02-live.mp4` | video | 16 s |
| 3 | `03-animations.mp4` | video | 18.5 s |
| 4 | `04-customize.mp4` | video | 10 s |
| 5 | `05-time.mp4` | video | 6 s |
| 6 | `06-touchid.mp4` | video | 8 s |
| 7 | `07-photo.mp4` | video | 8 s |
| 8 | `08-build.mp4` | video | 8 s |
| 9 | `09-plugins.mp4` | video | 9.5 s |
| 10 | `10-settings.mp4` | video | 10 s |
| 11 | `11-agents.mp4` | video | 10 s |
| 12 | `12-privacy.png` | still | |
| 13 | `13-safety.png` | still | |
| 14 | `14-rex.mp4` | video | 13 s |
| 15 | `15-link.png` | still | |

## The posts

**1/** `01-themes.mp4`

> 1/ Locky has 43 themes. Here is every one of them, with its name.

**2/** `02-live.mp4`

> 2/ The wallpapers are live. Each one is a Metal shader, and you can write your own. They stop in Low Power Mode.

**3/** `03-animations.mp4`

> 3/ Seven lock animations: Focus, Fade, Iris, Lift, Sweep, Dissolve, Tiles. Pick one in Settings › Lock Screen.

**4/** `04-customize.mp4`

> 4/ Every theme is yours to change. Drag the clock, add widgets (27 of them, in up to 6 sizes), change the
> background. You edit the live lock screen, in the app.

**5/** `05-time.mp4`

> 5/ Lookout follows the real time of day, from dawn to a starry night. A schedule can switch themes for you too:
> one by day, one by night.

**6/** `06-touchid.mp4`

> 6/ The Touch ID button can show Locky's lock instead of the macOS lock screen. It is one switch in Settings ›
> General, off by default, and it needs Accessibility access.

**7/** `07-photo.mp4`

> 7/ Wrong password? Locky can take a photo with the camera after 2, 3, 5, or 10 wrong tries. It keeps the newest 20
> for 30 days, in a folder only you can open.

**8/** `08-build.mp4`

> 8/ Start a theme from nothing in the app. Or write one: themes and widgets are Lua files. Or ask your coding
> agent: Locky ships its own agent skill.

**9/** `09-plugins.mp4`

> 9/ Themes and widgets install from any git repository: Settings › Plugins, a repository, Install. A plugin is code
> that runs as you, so install the ones you trust.

**10/** `10-settings.mp4`

> 10/ Locky locks by itself: after idle minutes, when the display turns off, when the Mac sleeps. Every switch is
> also a key in ~/.config/locky/settings.json, so it goes in your dotfiles.

**11/** `11-agents.mp4`

> 11/ Lock your MacBook and your agents keep working. A Locky lock is Locky's own windows over your session: macOS
> keeps running behind it.

**12/** `12-privacy.png`

> 12/ Hide personal information: one switch takes your name, your picture, the Mac's name, and your location off
> the lock screen.

**13/** `13-safety.png`

> 13/ If Locky crashes or hangs during a lock, a second process shows the macOS lock screen within 8 seconds.
> ⌃⌥⌘Q switches to it at any time. Only your password or Touch ID unlocks.

**14/** `14-rex.mp4` (your own words: you said you would write this one)

> 14/ I made a Rex theme too.

**15/** `15-link.png`

> 15/ Locky for macOS: github.com/InsaneArts/locky

## Before posting

- **The Touch ID clip shows no key press.** The switch is the real Settings window. The lock after it is Locky's
  own lock animation, played by `locky preview --transition` over a screenshot of the Themes window. A screenshot
  run starts no Touch ID tap, and the helper has no key to press. Press the button on your Mac before you post
  this, and consider a phone shot of the press in its place: it proves more.
- **The photo clip shows the menu only.** No photo was taken and no wrong password was typed. A choice in the menu
  makes macOS ask for the camera, the camera would show your room, and a preview checks the real login password.
- **Plugins.** The clip installs someone/locky-harbor, a made-up name for the docs' example theme. No public
  package for Locky exists yet.
- **Agents.** macOS's own lock screen does not stop your agents either. The post says what a Locky lock is, not
  that others stop them.
- **The link.** InsaneArts/locky is public under the MIT license since Nov 13, with release 0.1.0. Its README has
  the install lines: `curl … | sh`, Homebrew, or a build from a clone.
- **Settings.** The takes show "Version 0.0.1" in the sidebar, and "Device Control and Data Access", which is
  macOS 27's name for Accessibility.
- **Sound.** Each clip has a part of the film's score at the film's level. Nobody has heard them: listen once.
- **Size.** 1080p only. X plays 1080p at most; ask for 4K if another place needs it.
