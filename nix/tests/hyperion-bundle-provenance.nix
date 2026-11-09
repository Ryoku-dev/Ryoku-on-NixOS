# Evaluation-only checks of the Hyperion bundles. Store paths are compared
# instead of package names, so a renamed or rebuilt derivation cannot pass.
{
  pkgs,
  hyperionRyoku,
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
  upstreamPaths = hyperionRyoku.bundle.paths;

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
    ryotunes
    ryomanager
    qmkHid
    waifu2x
  ];
in

assert lib.assertMsg (mismatched == [ ])
  "Hyperion attrset diverges from the pinned flake outputs: ${toString mismatched}";

# The NixOS bridges come first in both bundles.
assert outs (lib.take bridgeCount niriPaths) == outs bridges;
assert outs fullBundle.paths == outs (bridges ++ [ hyperionPackages.ryoku-desktop ]);

# The full bundle is still upstream's complete bundle, Hyprland included.
assert has upstreamPaths hyperionRyoku.wmHyprland;

# Niri-only is exactly upstream's bundle minus wmHyprland. A component
# upstream adds or removes fails here until the list in flake.nix follows.
assert lib.assertMsg
  (sorted niriComponents
    == sorted (lib.filter (p: out p != hyperionRyoku.wmHyprland.outPath) upstreamPaths))
  "Niri-only Hyperion bundle no longer matches upstream's bundle without wmHyprland";

assert !(has niriPaths hyperionRyoku.wmHyprland);
assert !(has niriPaths hyperionRyoku.hyprPlugins);
assert lib.all (has niriComponents) required;

pkgs.writeText "ryoku-hyperion-bundle-provenance-check" "ok\n"
