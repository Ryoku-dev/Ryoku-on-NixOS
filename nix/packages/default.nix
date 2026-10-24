{
  pkgs,
  src,
  hyprglassSrc,
  bibataMaterialSrc,
  imgbordersSrc,
  ryomanagerSrc,
  ryotunesSrc,
  skwdPaper,
  version,
}:

let
  qmlRoot = "lib/qt-6/qml";

  shell = import ./ryoku-shell.nix {
    inherit pkgs src;
  };

  desktopData = import ./ryoku-desktop-data.nix {
    inherit pkgs src;
  };

  wmHyprland = import ./ryoku-wm-provider.nix {
    inherit pkgs src;
    provider = "hyprland";
  };

  wmNiri = import ./ryoku-wm-provider.nix {
    inherit pkgs src;
    provider = "niri";
  };

  wmMango = import ./ryoku-wm-provider.nix {
    inherit pkgs src;
    provider = "mango";
  };

  # Niri 26.04 retains layer-shell surfaces when a physical output is
  # removed, so repeated DPMS/hotplug cycles accumulate their buffers.
  # Upstream PR #4485 fixes #1457 by cleaning each output's layer map before
  # removing the output from the layout. Keep the patch vendored and pinned so
  # Ryoku builds remain reproducible while the upstream fix is still open.
  ryokuNiri = pkgs.niri.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ../patches/niri-output-layer-cleanup.patch
    ];
  });

  # Ryoku 0.82.2 targets Mango 0.17.4. The package in Ryoku's
  # deliberately pinned nixpkgs universe is still 0.16.1, so keep
  # the dependency ABI from that universe while updating the source.
  ryokuMango = pkgs.mango.overrideAttrs (_old: {
    pname = "ryoku-mango";
    version = "0.17.4";

    src = pkgs.fetchFromGitHub {
      owner = "mangowm";
      repo = "mango";
      tag = "0.17.4";
      sha256 = "1n9mbbf9g2h3lk3h8v084s2drvzq5zc0im5fr6ck5ycpgg0xhf38";
    };
  });

  xwaylandSatellite = import ./xwayland-satellite.nix {
    inherit pkgs;
  };

  cli = import ./ryoku-cli.nix {
    inherit
      pkgs
      src
      version
      desktopData
      paletteBridge
      ;
  };

  nixUpdate = import ./ryoku-nix-update.nix {
    inherit pkgs src;
  };

  hub = import ./ryoku-hub.nix {
    inherit pkgs src paletteBridge desktopData;
  };

  paletteBridge = import ./ryoku-palette-bridge.nix {
    inherit pkgs src;
  };

  rashin = import ./ryoku-rashin.nix {
    inherit pkgs src desktopData;
  };

  prowlAgent = import ./prowl-agent.nix {
    inherit pkgs;
  };

  ryostore = import ./ryoku-ryostore.nix {
    inherit pkgs src;
  };

  ryomotion = import ./ryoku-ryomotion.nix {
    inherit pkgs;
  };

  ryovmHelpers = import ./ryoku-ryovm-helpers.nix {
    inherit pkgs src;
  };

  livewall = import ./ryoku-livewall.nix {
    inherit pkgs src;
  };

  qmkHid = import ./qmk-hid.nix {
    inherit pkgs;
  };

  waifu2x = import ./waifu2x-ncnn-vulkan.nix {
    inherit pkgs;
  };

  ryogami = import ./ryoku-ryogami.nix {
    inherit
      pkgs
      src
      livewall
      waifu2x
      qmlRoot
      paletteBridge
      ;
  };

  ryotunesUnwrapped = import ./ryotunes-unwrapped.nix {
    inherit pkgs ryotunesSrc;
  };

  ryotunes = import ./ryoku-ryotunes.nix {
    inherit pkgs ryotunesUnwrapped;
    ryokuQml = qml;
  };

  ryomanager = import ./ryomanager.nix {
    inherit pkgs ryomanagerSrc;
  };

  keysounds = import ./ryoku-keysounds.nix {
    inherit pkgs src;
  };

  helpers = import ./ryoku-helpers.nix {
    inherit pkgs src;
  };

  hyprglass = import ./ryoku-hyprglass.nix {
    inherit pkgs;
    src = hyprglassSrc;
  };

  imgborders = pkgs.hyprlandPlugins.imgborders.overrideAttrs (_: {
    pname = "ryoku-imgborders";
    version = "unstable";
    src = imgbordersSrc;
  });

  hyprPlugins = import ./ryoku-hypr-plugins.nix {
    inherit
      pkgs
      hyprglass
      imgborders
      keysounds
      ;
  };

  cursorMaterial = import ./ryoku-cursor-material.nix {
    inherit pkgs;
    ryokuSrc = src;
    bibataSrc = bibataMaterialSrc;
  };

  mapleMonoNF = import ./ryoku-maple-mono-nf.nix {
    inherit pkgs;
  };

  nixosSystemBridge = import ./ryoku-nixos-system-bridge.nix {
    inherit pkgs src;
  };

  blobs = import ./ryoku-blobs.nix {
    inherit pkgs src qmlRoot;
  };


  mkPureQmlModule =
    {
      pname,
      moduleName,
      sourcePath,
      description,
    }:
    pkgs.stdenvNoCC.mkDerivation {
      inherit pname;

      version = "unstable";
      src = src + sourcePath;

      dontBuild = true;

      installPhase = ''
        runHook preInstall

        dest="$out/${qmlRoot}/Ryoku/${moduleName}"

        mkdir -p "$dest"
        cp -a ./. "$dest/"

        rm -f "$dest/install.sh"

        runHook postInstall
      '';

      meta = {
        inherit description;
        homepage = "https://github.com/Ryoku-dev/ryoku-arch";
        license = pkgs.lib.licenses.gpl3Only;
        platforms = [ "x86_64-linux" ];
      };
    };

  ui = mkPureQmlModule {
    pname = "ryoku-ui";
    moduleName = "Ui";
    sourcePath = "/ryoku/ui";
    description = "Shared Ryoku Qt/QML user interface module";
  };

  pluginKit = mkPureQmlModule {
    pname = "ryoku-plugin-kit";
    moduleName = "PluginKit";
    sourcePath = "/ryoku/shell/quickshell/plugins/kit";
    description = "Ryoku shell plugin Qt/QML framework";
  };

  frameBars = mkPureQmlModule {
    pname = "ryoku-framebars";
    moduleName = "FrameBars";
    sourcePath = "/ryoku/shell/framebars";
    description = "Ryoku FrameBars Qt/QML module";
  };

  wmHyprlandQml = mkPureQmlModule {
    pname = "ryoku-wm-hyprland-qml";
    moduleName = "Wm/Hyprland";
    sourcePath = "/ryoku/wm/hyprland/qml";
    description = "Ryoku Hyprland-specific Qt/QML bridge module";
  };

  qml = pkgs.runCommand "ryoku-qml-modules" {
    meta = {
      description = "Combined Ryoku Qt/QML module tree";
      homepage = "https://github.com/Ryoku-dev/ryoku-arch";
      license = pkgs.lib.licenses.gpl3Only;
      platforms = [ "x86_64-linux" ];
    };
  } ''
    mkdir -p "$out/${qmlRoot}/Ryoku"

    cp -a \
      ${ui}/${qmlRoot}/Ryoku/Ui \
      "$out/${qmlRoot}/Ryoku/Ui"

    cp -a \
      ${pluginKit}/${qmlRoot}/Ryoku/PluginKit \
      "$out/${qmlRoot}/Ryoku/PluginKit"

    cp -a \
      ${frameBars}/${qmlRoot}/Ryoku/FrameBars \
      "$out/${qmlRoot}/Ryoku/FrameBars"

    mkdir -p "$out/${qmlRoot}/Ryoku/Wm"

    cp -a \
      ${wmHyprlandQml}/${qmlRoot}/Ryoku/Wm/Hyprland \
      "$out/${qmlRoot}/Ryoku/Wm/Hyprland"

    cp -a \
      ${blobs}/${qmlRoot}/Ryoku/Blobs \
      "$out/${qmlRoot}/Ryoku/Blobs"

    cp -a \
      ${blobs}/${qmlRoot}/Ryoku/Spatial3D \
      "$out/${qmlRoot}/Ryoku/Spatial3D"
  '';

  bundle = pkgs.symlinkJoin {
    name = "ryoku-desktop-bundle";

    meta = {
      description = "Complete Ryoku desktop runtime bundle";
      homepage = "https://github.com/Ryoku-dev/ryoku-arch";
      license = pkgs.lib.licenses.gpl3Only;
      platforms = [ "x86_64-linux" ];
    };

    paths = [
      shell
      cli
      nixUpdate
      hub
      paletteBridge
      rashin
      prowlAgent
      ryostore
      ryomotion
      ryovmHelpers
      livewall
      ryogami
      skwdPaper
      ryotunes
      ryomanager
      qmkHid
      waifu2x
      desktopData
      wmHyprland
      wmNiri
      wmMango
      helpers
      nixosSystemBridge
      qml
    ];
  };
in
{
  niri = ryokuNiri;
  mango = ryokuMango;

  inherit
    shell
    cli
    nixUpdate
    hub
    paletteBridge
    rashin
    prowlAgent
    ryostore
    ryomotion
    ryovmHelpers
    livewall
    ryogami
    skwdPaper
    ryotunes
    ryomanager
    ryotunesUnwrapped
    keysounds
    qmkHid
    waifu2x
    desktopData
    wmHyprland
    wmNiri
    wmMango
    helpers
    nixosSystemBridge
    hyprglass
    imgborders
    hyprPlugins
    cursorMaterial
    mapleMonoNF

    ui
    pluginKit
    frameBars
    wmHyprlandQml
    blobs
    qml

    xwaylandSatellite

    bundle
    ;
}
