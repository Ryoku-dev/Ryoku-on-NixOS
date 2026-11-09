# Evaluation-only checks of the Hyperion bundles. Store paths are compared
# instead of package names, so a renamed or rebuilt derivation cannot pass.
{
  pkgs,
  hyperionRyoku,
  hyperionRyotunes,
  hyperionPackages,
  bridges,
  fullBundle,
  niriBundle,
}:
let
  inherit (pkgs) lib;

  out = p: if builtins.isAttrs p then p.outPath else toString p;
  outs = map out;
  sorted = list: lib.sort builtins.lessThan (outs list);
  has = list: p: lib.elem (out p) (outs list);

  # The imported attrset must reproduce the pinned flake's outputs exactly.
  reproduced = {
    shell = "ryoku-shell";
    cli = "ryoku-cli";
    hub = "ryoku-hub";
    desktopData = "ryoku-desktop-data";
    qml = "ryoku-qml";
    wmHyprland = "ryoku-wm-hyprland";
    wmNiri = "ryoku-wm-niri";
    ryostore = "ryoku-ryostore";
    ryogami = "ryoku-ryogami";
    ryoport = "ryoport";
    bundle = "ryoku-desktop";
  };

  mismatched = lib.filter
    (attr: hyperionRyoku.${attr}.outPath != hyperionPackages.${reproduced.${attr}}.outPath)
    (lib.attrNames reproduced);

  bridgeCount = lib.length bridges;
  niriPaths = niriBundle.paths;
  niriComponents = lib.drop bridgeCount niriPaths;
  fullComponents = lib.drop bridgeCount fullBundle.paths;
  upstreamPaths = hyperionRyoku.bundle.paths;
  without = drop: lib.filter (p: !(lib.elem (out p) (outs drop)));

  # Upstream's bundle with Ryotunes 1.2.0 replaced by the release Arch ships.
  expectedFull = without [ hyperionRyoku.ryotunes ] upstreamPaths ++ [ hyperionRyotunes ];

  # Core shell, CLI, Hub, Ryogami, Niri and every v2 app.
  required = with hyperionRyoku; [
    shell
    cli
    hub
    qml
    desktopData
    helpers
    paletteBridge
    wmNiri
    ryogami
    rashin
    prowlAgent
    ryostore
    ryomotion
    ryoport
    livewall
    skwdPaper
    ryomanager
    qmkHid
    waifu2x
  ];
in

assert lib.assertMsg (mismatched == [ ])
  "Hyperion attrset diverges from the pinned flake outputs: ${toString mismatched}";

# The NixOS bridges come first in both bundles.
assert outs (lib.take bridgeCount niriPaths) == outs bridges;
assert outs (lib.take bridgeCount fullBundle.paths) == outs bridges;

assert lib.assertMsg (sorted fullComponents == sorted expectedFull)
  "full Hyperion bundle no longer matches upstream's bundle with the Ryotunes release";
assert has fullComponents hyperionRyoku.wmHyprland;

# Niri-only is exactly that minus wmHyprland.
assert lib.assertMsg
  (sorted niriComponents == sorted (without [ hyperionRyoku.wmHyprland ] expectedFull))
  "Niri-only Hyperion bundle no longer matches upstream's bundle without wmHyprland";

# Exactly one Ryotunes: the release build, never upstream's 1.2.0 pin.
assert !(has fullComponents hyperionRyoku.ryotunes);
assert !(has niriComponents hyperionRyoku.ryotunes);
assert has niriComponents hyperionRyotunes;

assert !(has niriPaths hyperionRyoku.wmHyprland);
assert !(has niriPaths hyperionRyoku.hyprPlugins);
assert lib.all (has niriComponents) required;

pkgs.writeText "ryoku-hyperion-bundle-provenance-check" "ok\n"
