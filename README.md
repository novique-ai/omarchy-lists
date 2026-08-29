# Lists

Checklists for [Omarchy](https://omarchy.org/). A **Lists** item sits on the
menu bar; the same command is on the Super menu. Click it to open a window.

- Sidebar of open lists, plus an **Archived** section
- Check buttons that toggle
- Nested items (`Tab` / `Shift+Tab`)
- Optional due dates (`YYYY-MM-DD`; overdue turns urgent)
- Click a title or item to rename it
- **Archive** when a list is done; **Unarchive** or **Delete** from the archive

Lists are stored in `~/.local/state/omarchy/lists/lists.json`.

## Install

```bash
omarchy plugin add https://github.com/novique-ai/omarchy-lists.git --enable
```

That clones the plugin into `~/.config/omarchy/plugins/novique.lists/` and
places **Lists** on the right of the bar. Add a Super-menu entry if you want
one:

```jsonc
"lists": {
  "icon": "󰷉",
  "label": "Lists",
  "description": "Simple checklists",
  "action": "omarchy-shell shell summon novique.lists '{}'"
}
```

in `~/.config/omarchy/extensions/omarchy-menu.jsonc`.

To float the window instead of tiling it, add to `~/.config/hypr/hyprland.lua`:

```lua
o.window({ class = "^org.quickshell$", title = "^Lists$" }, {
  float = true,
  center = true,
  size = { 840, 560 },
})
```

## Use

| Action | How |
|---|---|
| Open | Menu bar icon, Super menu → Lists, or `omarchy-shell shell summon novique.lists` |
| New list | **New list**, or `n` |
| Add item | Type in **Add an item**, Enter |
| Check | Click the square |
| Nest / un-nest | `Tab` / `Shift+Tab` |
| Due date | Click **due**, type `YYYY-MM-DD`, Enter. Blank clears. |
| Archive | **Archive**, sidebar ↓, or `e` |
| Close | Esc |

## Remove

```bash
omarchy plugin remove novique.lists
```

That drops the plugin. Your lists file is left in
`~/.local/state/omarchy/lists/` so a later install can pick it up. Delete that
directory if you want the data gone too.

## Develop

```bash
node --test tests/*.test.js
omarchy plugin validate .
```

Edits under `~/.config/omarchy/plugins/novique.lists/` reload in the running
shell.
