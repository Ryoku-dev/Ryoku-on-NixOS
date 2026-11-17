{ pkgs, src }:

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "hyprglass";
  version = "1.1.1";

  inherit src;

  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    pkgs.pkg-config
    pkgs.wayland-scanner
  ];

  buildInputs = [
    pkgs.hyprland
  ];

  inputsFrom = [
    pkgs.hyprland
  ];

  buildPhase = ''
    runHook preBuild
    make -j"$NIX_BUILD_CORES"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 \
      hyprglass.so \
      "$out/lib/hyprglass.so"

    runHook postInstall
  '';

  meta = {
    description = "HyprGlass built against Ryoku's NixOS Hyprland";
    homepage = "https://github.com/hyprnux/hyprglass";
    license = pkgs.lib.licenses.bsd3;
    platforms = pkgs.lib.platforms.linux;
  };
}
