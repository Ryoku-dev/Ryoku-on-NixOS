{ pkgs, ryokuSrc, bibataSrc }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "ryoku-cursor-material";
  version = "1.0.0";

  src = ryokuSrc;

  nativeBuildInputs = [
    pkgs.makeWrapper
    pkgs.fish
    pkgs.jq
    pkgs.python3
    pkgs.librsvg
    pkgs.xcursorgen
  ];

  buildPhase = ''
    runHook preBuild

    work="$TMPDIR/ryoku-cursor-material"
    mkdir -p "$work/scripts"

    cp \
      release/packages/ryoku-cursor-material/themes.json \
      "$work/themes.json"

    cp \
      release/packages/ryoku-cursor-material/compile_bibata_material.fish \
      release/packages/ryoku-cursor-material/metadata_generator.py \
      "$work/scripts/"

    cp -R \
      ${bibataSrc} \
      "$work/scripts/bibata_cursor"

    # Inputs copied out of the Nix store retain read-only modes. The compiler
    # edits render.json in its private build tree, so make that tree writable.
    chmod -R u+w "$work"

    # The upstream cursor tools use /usr/bin/env shebangs and fish writes
    # history/cache state. Pure Nix builders provide neither /usr/bin/env nor
    # a writable default HOME, so normalize both inside the build sandbox.
    export HOME="$TMPDIR/home"
    export XDG_CONFIG_HOME="$TMPDIR/xdg-config"
    export XDG_DATA_HOME="$TMPDIR/xdg-data"
    export XDG_CACHE_HOME="$TMPDIR/xdg-cache"

    mkdir -p \
      "$HOME" \
      "$XDG_CONFIG_HOME" \
      "$XDG_DATA_HOME" \
      "$XDG_CACHE_HOME"

    patchShebangs "$work"

    export BIBATA_MATERIAL_INSTALL_DIR="$work/out"

    ${pkgs.fish}/bin/fish \
      "$work/scripts/compile_bibata_material.fish" \
      Ryoku

    theme="$work/out/Bibata-Material-Ryoku"

    test -d "$theme/cursors"
    test -n "$(find "$theme/cursors" -type f -print -quit)"

    test -d "$theme/hyprcursors"
    test -n "$(find "$theme/hyprcursors" -type f -print -quit)"

    test -f "$theme/manifest.hl"
    test -f "$theme/index.theme"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    data="$out/share/ryoku-cursor-material/bibata"

    mkdir -p \
      "$data" \
      "$out/bin" \
      "$out/share/icons"

    # Offline fallback used before the first dynamic recolour and whenever the
    # palette hook has not yet produced a per-user copy.
    cp -a \
      "$TMPDIR/ryoku-cursor-material/out/Bibata-Material-Ryoku" \
      "$out/share/icons/"

    # Source used by the runtime recolour helper.
    cp -a ${bibataSrc}/src "$data/src"
    cp -a ${bibataSrc}/svg "$data/svg"
    cp -a ${bibataSrc}/config "$data/config"

    install -Dm755 \
      release/packages/ryoku-cursor-material/ryoku-cursor-material-recolor \
      "$out/bin/ryoku-cursor-material-recolor"

    substituteInPlace "$out/bin/ryoku-cursor-material-recolor" \
      --replace-fail \
        '/usr/share/ryoku-cursor-material/bibata' \
        "$data"

    wrapProgram "$out/bin/ryoku-cursor-material-recolor" \
      --prefix PATH : ${pkgs.lib.makeBinPath [
        pkgs.python3
        pkgs.librsvg
        pkgs.xcursorgen
        pkgs.hyprland
      ]}

    runHook postInstall
  '';

  meta = {
    description = "Ryoku wallpaper-accent Material Bibata cursor helper";
    homepage = "https://github.com/SakibShahariar/material-bibata-cursor";
    license = with pkgs.lib.licenses; [ gpl3Plus mit ];
    platforms = pkgs.lib.platforms.linux;
  };
}
