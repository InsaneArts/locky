# Make widgets and themes with a coding agent

Locky ships a skill for coding agents, such as Claude Code and Codex. With it, an agent writes a widget or a theme
from what you describe, checks it with Locky's command line, draws it to a picture, and fixes it until it looks
right.

## Install the skill

In Settings › Customization, click Install in the Agent skill row. Or run:

```sh
/Applications/Locky.app/Contents/MacOS/Locky skill install
```

Locky copies the skill to each agent whose folder is in your home folder:

| Agent | Folder |
|---|---|
| Claude Code | `~/.claude/skills/locky` |
| Codex | `~/.codex/skills/locky` |
| Other agents that read `~/.agents` | `~/.agents/skills/locky` |

Locky does not make these agent folders. Install the agent first. A new Locky can ship a newer skill: the row then
says Update, and `locky skill install` replaces the old copy. `locky skill path` prints the skill folder that
Locky ships.

## Ask

Start your agent and describe what you want. Name Locky, so the agent uses the skill:

- "Make a Locky widget that shows the days until my vacation on December 20."
- "Make a Locky widget that shows my unread GitHub notifications. Use the gh command."
- "Make a Locky theme in the colors of a Tokyo night, with a large clock and the weather."
- "Move the battery widget in my Locky theme to the top right, and make it smaller."
- "My Locky init.lua has an error. Fix it."

## What the agent does

1. It writes Lua files in your config folder, `~/.config/locky`: a widget in `plugin/`, a theme in `themes/`.
2. It runs `locky check`, which runs the files and lists each error with its file and line.
3. It runs `locky render`, which draws the lock screen to a PNG with privacy mode on and without a window. Then
   it looks at the picture.
4. It fixes what it sees and repeats until the check passes and the picture is right.

The skill tells the agent the rules that keep the lock screen safe, and to test with `render`, never with a lock.

## Check its work

- Read the files it wrote. A widget runs as you, as every plugin does: see
  [plugins.md](plugins.md#the-rules-that-keep-the-lock-screen-safe).
- Run the checks yourself:

  ```sh
  locky check --widget NAME
  locky render --theme default --widget NAME --out /tmp/widget.png && open /tmp/widget.png
  ```

- Open Themes, choose Customize… on a theme, and add the widget with Add Widget…. The next lock shows it.

To write a widget yourself, follow [create-widget.md](create-widget.md).
