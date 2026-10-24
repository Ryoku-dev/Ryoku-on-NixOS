# Shima Module SDK

Shima bar modules use the existing CustomWidgets registry. There is no second plugin format or
scanner. A widget may provide its normal desktop component, a Shima compact component, or both.

## Create a module

Copy `defaults/widgets/example-widget/` into `~/.config/inir/widgets/<name>/`, then add the `iris`
manifest block and compact component described below. CustomWidgets watches the directory and
reloads installed widgets after edits.

Turn it on in **Shima Settings > Island > Desktop page > Your modules** (the row shows up once a module is installed; search for "modules"). It
lands in the Modules block of the Island's Desktop page. Material's Settings has the same switch
under **Shima > Modules**.

## Manifest

```json
{
  "name": "My Widget",
  "main": "MyWidget.qml",
  "iris": {
    "main": "IrisCompact.qml",
    "slots": ["island.desktop"]
  }
}
```

`slots` is optional. Right now there is one place a module can live, the Island's Desktop page, and
the component gets it as `irisSlot` (`"island.desktop"`). Declaring it keeps the manifest honest
for when there are more.

The module list is `iris.bar.rightModules`, ordered, with entries like `"custom:my-widget"`. Settings
writes it for you; no other registration is needed.

## Minimal compact component

```qml
pragma ComponentBehavior: Bound

import QtQuick
import inir.services
import inir.modules.iris.style
import inir.modules.iris.components

Item {
    property string irisSlot: ""
    property var targetScreen

    implicitWidth: row.implicitWidth
    implicitHeight: Math.round(28 * IrisStyle.density)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: IrisStyle.spaceSmall

        IrisMark { implicitSize: Math.round(14 * IrisStyle.density) }
        IrisText {
            role: IrisText.Meta
            text: DateTime.timeDisplay
            font.family: IrisStyle.fontNumbers
        }
    }
}
```

## Compact API

Use these first:

- `IrisStyle`: colors, fonts, density, radii, spacing, motion duration and text sizes
  (`typeCaption` 10, `typeFootnote` 11, `typeMeta` 12, `typeLabel` 13, `typeBody` 14,
  `typeHeadline` 15, `typeTitle` 17, `typeTitleLarge` 21, `typeDisplay` 28). Use those instead of
  `N * typeScale`, and keep spacing on even steps of `IrisStyle.density` (2, 4, 6, 8, 10, 12…);
- `IrisText`: roles that set size, weight and ink together (`Body`, `Meta`, `Title`, `Display`,
  `Metric`, `Eyebrow`);
- `IrisSurface`: normal/raised surface;
- `IrisButton` / `IrisIconButton`: hover/tap/selected states;
- `IrisSegmented` and `IrisSwitch`: the same segmented control and switch Shima Settings uses;
- `IrisMark`: family mark;
- `IrisSlider`: compact slider (use `IrisCapsuleSlider` for Control Center style levels).

Looks that fit: a group is a fill (`IrisStyle.fillQuiet`), not a bordered box; a control carries its
state in its fill and ink, not in a badge next to it; colour means something (accent for on or
selected, identity hues for a fixed meaning), never decoration.

Normal Shima services remain available through `import inir.services`, but a compact module should
import only what it actually needs. Avoid pulling in media visualizers, preview services or
background processes for a value that is not continuously visible.

## Lifecycle rules

- Do not start a subprocess from a hidden component just to cache data.
- Do not use a permanent animation for decoration.
- Prefer service signals over polling timers.
- Keep module failure local; do not mutate family loader state.
- Respect `targetScreen` for output-specific data.
- Use `Config.setNestedValue(...)` for persistent writes; do not assign into `Config.options`.
- Keep presentation in Shima tokens rather than hard-coded theme colors.

For full desktop-widget APIs and the broader service/component catalog, see `WIDGET-SDK.md`.

Based on iNiR by snowarch (https://github.com/snowarch/inir)

See [NOTICE](../../NOTICE) for upstream attribution and additional terms.
