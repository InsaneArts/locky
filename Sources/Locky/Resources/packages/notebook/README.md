# Notebook

A page of a ruled school notebook: the time in marker, the day and your to-do list by hand, a sticky note saying you
will be back, and a coffee ring.

```lua
locky.setup({ theme = "notebook" })
```

## What it shows

- The time in Marker Felt, the date and the time in words in Bradley Hand.
- `notebook.todo`: your to-do list from `~/todo.txt` ([todo.txt format](https://github.com/todotxt/todo.txt): `x `
  marks a task done, `(A) ` gives it a priority) or from a Markdown file's `- [ ]` task lines. Open tasks come first,
  by priority; done ones last, ticked in red. Read again every minute. Without the file it shows how to start one.
  Privacy mode shows only how many tasks are left. Options: `path`, `rows`, `title`, `width`.

  ```lua
  locky.setup({ widgets = { ["notebook.todo"] = { path = "~/notes/today.md" } } })
  ```
- `notebook.sticky`: a sticky note, "Back soon!", with the time the screen locked. Options: `text`, `paper`,
  `rotation`.
- `notebook.weather`: the weather, written in the margin.
- The `notebook` shader draws the page once: blue rules, a red margin, three punched holes, and a coffee ring. Its
  colors are the paper, the rules, the margin, the desk, and the coffee. Parameter 1 sets the rules per screen height
  (default 30); parameter 2 the margin's distance from the left, as a fraction of the width (default 0.11).
