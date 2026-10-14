# The QS Bar and the dock

The default Ryoku bar is **Orpheus** (`orpheus`): drops on the top edge with a
voice in the middle for the time, music, notifications, and recordings. The
Sound page's gain slider sets how much the bar reacts to music. Its Bar settings
page picks a liquid or square form; the square one keeps crisp corners and shows
sound as blocks. Left-click its 力 logo to open its settings, where the Layout
page arranges its modules by drag and drop; right-click the logo for the
launcher. Its keys live under `orpheus` in `shell.json` and are listed in
`docs/barstyles.md`. Pick another style with `ryoku-shell barstyle <id>`, for
example `ryoku-shell barstyle qsbar`.

**QS Bar** (`qsbar`) remains a built-in choice. Its layout is data, not code: it
lives in `~/.config/ryoku/shell.json` under `qsbar.layout`, and every built-in
widget and every installed plugin is an entry in the same list. Drive it with
`ryoku-shell bar ...`; the shell daemon is the only writer of `shell.json`, so
never hand-edit the layout.

The other shipped choices use their own models and are not covered here. Sumi
is the monochrome frame rail, Kairos is a growing clock island, and Shima,
Python, and Nomarchy are complete frame families.

## The layout model

```json
"qsbar": {
  "layout": {
    "version": 1,
    "left":   ["launcher", "workspaces", "status", "cpu", "volume", "memory", "ai"],
    "center": ["clock"],
    "right":  ["media", "quick", "network", "power", "battery", "brightness",
               "cputemp", "storage", "gpu", "bluetooth", "layout"]
  },
  "widgets": { "status": true, "memory": true }
}
```

- An entry is a **widget id**: a built-in from the catalogue, or an installed
  plugin's manifest id. Order within a section is the order on the bar.
- **Placement and visibility are separate.** `qsbar.layout` holds only order and
  section. Whether a built-in renders is `qsbar.widgets[<visKey>]` (a widget with
  no visibility key is always shown). A plugin renders when
  `~/.config/ryoku/plugins.json` has it `enabled` with `host: "topbarGlyph"`.
  `ryoku-shell bar list` reports both as one `shown` flag, so you never have to
  know which store answers.
- Every id appears at most once. A known widget missing from the layout is
  appended to `right` (or to its manifest's `defaults.bar.section`). Duplicates
  are dropped.
- Presentation keys keep their own homes and are not placement: `qsbar.barSeps`
  (separators), `qsbar.iconOnlyGids` (density), `qsbar.widgetColorStyles`
  (per-widget colour), and the bar-shell keys `barPosition`, `barShellStyle`,
  `barScale`, `barCornerRadius`, `barBorderEnabled`, `barFrostEnabled`,
  `barShadowEnabled`, `barAutoHide`, `barAnim`, `barGap*`.

## The catalogue

One file names every built-in widget: its id, its `G1..G19` internal slot, label,
gloss, category, description, visibility key, and its own settings. The shell, the
settings panel, the `ryoku-shell bar` CLI, and Rashin all read it, so nothing
hand-lists widgets. It ships at
`~/.config/quickshell/shell/modules/bar/barstyles/qsbar/core/widgets.json`.

The eighteen shipped ids and their visibility keys (a blank key means always
shown):

| id | label | visibility key (`qsbar.widgets.*`) |
|---|---|---|
| launcher | Launcher | (always) |
| workspaces | Workspaces | (always) |
| status | Status | status |
| memory | Memory | memory |
| cpu | CPU | cpu |
| volume | Volume | volume |
| ai | AI usage | claude |
| clock | Clock | (always) |
| media | Now playing | mpris |
| quick | Quick | quick |
| network | Network | network |
| battery | Battery | battery |
| brightness | Brightness | brightness |
| power | Power | power |
| bluetooth | Bluetooth | bluetooth |
| cputemp | CPU temperature | cpuTemperature |
| gpu | GPU | gpu |
| storage | Storage | storage |
| layout | Keyboard layout | layout |

Run `ryoku-shell bar catalog` for the live list including each widget's own
settings (and any installed plugins that ride the bar).

## The bar CLI

Every verb goes through the daemon's settings store; a bad id, key, or value is
an error (`err bar: <reason>`), never a silent write.

```
bar list [--json]                 every widget: id, label, kind, section, index, shown
bar catalog [--json]              built-ins and installed bar-capable plugins, with settings
bar move <id> --section <s> [--index N | --before <id> | --after <id>]
bar show <id> | bar hide <id>     toggle visibility, keeping placement
bar set <id> <key> <value>        a catalogue setting (built-in) or a manifest setting (plugin)
bar position top|bottom
bar form full|fit|dock|notch|islands
bar defaults                      shipped layout and visibility; presentation keys untouched
bar settings [route]              open QS Bar Settings on the active monitor
```

`--json` shapes:

- `bar list --json`: `[{"id","label","kind","section","index","shown"}]`, where
  `kind` is `"builtin"` or `"plugin"` and `section` is `left|center|right`.
- `bar catalog --json`: the merged catalogue, `{"id","label","gloss","category",
  "desc","kind","settings":[...],"pluginDir"}` per widget, plus `{"hosts":[...]}`
  for plugins.

Examples:

```bash
ryoku-shell bar move clock --section right --index 0
ryoku-shell bar hide gpu
ryoku-shell bar set cputemp barTemperatureSource gpu
ryoku-shell bar set volume audioBoost true
ryoku-shell bar position bottom
ryoku-shell bar form islands
ryoku-shell bar list --json
```

## The dock CLI

```
dock show | dock hide
dock edge auto|top|bottom|left|right
dock autohide on|off
dock pin <app-id> | dock unpin <app-id>
dock list [--json]
```

`dock list --json`: `{"enabled","edge","autohide","pinned":[...]}`. Dock state
lives under the `dock` object in `shell.json`.

```bash
ryoku-shell dock pin org.mozilla.firefox
ryoku-shell dock edge bottom
ryoku-shell dock autohide on
```

## Opening the settings panel

The bar and the dock have their own GUI, **QS Bar Settings**, not a Ryoku Hub
page; name it when a user asks how to change the bar from the desktop.

`ryoku-shell bar settings [route]` raises **QS Bar Settings** on the active
monitor (routes: `bars`, `layout`, `widgets`, `dock`, `community`). It is the
same panel the bar's launcher mark opens; Escape closes it. Layout lists the
three lanes side by side; a move there and a `bar move` from a terminal reach
the same `qsbar.layout`. Community lists every installed bar plugin that is not
Ryoku's own (a manifest without `"official": true`), with its author and a
REMOVE action; a plugin you write for the user lands there.
