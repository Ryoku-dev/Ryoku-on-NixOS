{
  pkgs,
  src,
}:

let
  mechvibesSrc = pkgs.fetchFromGitHub {
    owner = "hainguyents13";
    repo = "mechvibes";

    rev = "326252a13e7bef4f1c35d08ef0189b5af6f8ba02";

    # Exact source used by Ryoku 0.59.7 for the shipped switch
    # recording profiles.
    hash = "sha256-+pEyeTzOLQXwGltFuRGGzTl0jFz8Jwbj2/u8Yiu6nmE=";
  };
in

pkgs.hyprlandPlugins.mkHyprlandPlugin {
  pluginName = "ryoku-keysounds";
  version = "1.0";

  src =
    src + "/ryoku/hyprland/plugins/keysounds";

  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    pkgs.ffmpeg
    pkgs.gnumake
    pkgs.makeWrapper
    pkgs.python3
  ];

  buildInputs = [
    pkgs.libcanberra
  ];

  postPatch = ''
    # The upstream Makefile can clone Mechvibes and discovers the importer
    # through PATH. Nix builds are network-isolated, so provide both inputs
    # explicitly from immutable sources. The importer and profiles.txt live
    # in the shared ryoku/keysounds tree, outside this plugin source.
    cp \
      ${src}/ryoku/keysounds/ryoku-keysounds-import \
      ./ryoku-keysounds-import

    substituteInPlace \
      ./ryoku-keysounds-import \
      --replace-fail \
        '#!/usr/bin/env python3' \
        '#!${pkgs.python3}/bin/python3'

    chmod 755 \
      ./ryoku-keysounds-import

    # The upstream Arch build can be repaired from Settings. On NixOS
    # plugin ABI ownership belongs to the generation instead.
    substituteInPlace \
      main.cpp \
      --replace-fail \
        'rebuild it from Settings > Plugins' \
        'restart Hyprland after updating the NixOS Ryoku generation'
  '';

  buildPhase = ''
    runHook preBuild

    make \
      CXX="$CXX" \
      MECHVIBES="${mechvibesSrc}" \
      IMPORTER="$PWD/ryoku-keysounds-import" \
      PROFILES="${src}/ryoku/keysounds/profiles.txt" \
      keysounds.so \
      sounds

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p \
      "$out/bin" \
      "$out/lib" \
      "$out/share/doc/ryoku-keysounds"

    # Keep the sample directory beside the plugin. main.cpp deliberately
    # searches <directory-containing-.so>/keysounds before its FHS fallback.
    install -Dm755 \
      keysounds.so \
      "$out/lib/keysounds.so"

    cp -a \
      sounds \
      "$out/lib/keysounds"

    find "$out/lib/keysounds" \
      -type d \
      -exec chmod 755 {} +

    find "$out/lib/keysounds" \
      -type f \
      -exec chmod 644 {} +

    install -Dm755 \
      ./ryoku-keysounds-import \
      "$out/bin/ryoku-keysounds-import"

    wrapProgram \
      "$out/bin/ryoku-keysounds-import" \
      --prefix PATH : ${pkgs.lib.makeBinPath [
        pkgs.ffmpeg
      ]}

    install -Dm644 \
      README.md \
      "$out/share/doc/ryoku-keysounds/README.md"

    install -Dm644 \
      ${src}/ryoku/keysounds/profiles.txt \
      "$out/share/doc/ryoku-keysounds/profiles.txt"

    runHook postInstall
  '';

  meta = {
    description =
      "Ryoku Hyprland keyboard sound plugin and switch profiles";

    homepage =
      "https://github.com/Ryoku-dev/ryoku-arch";

    license = [
      pkgs.lib.licenses.gpl3Plus
      pkgs.lib.licenses.mit
    ];

    platforms = [
      "x86_64-linux"
    ];
  };
}
