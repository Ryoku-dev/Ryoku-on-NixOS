{ pkgs }:

let
  version = "20250802";
in
pkgs.stdenv.mkDerivation {
  pname = "waifu2x-ncnn-vulkan";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/nihui/waifu2x-ncnn-vulkan/releases/download/${version}/waifu2x-ncnn-vulkan-${version}-linux.zip";
    hash = "sha256-H8uk8Aw5+DV1VA02eaevraZaI4yzLuACY3XT1N6UpSs=";
  };

  nativeBuildInputs = [
    pkgs.unzip
    pkgs.autoPatchelfHook
    pkgs.makeWrapper
  ];

  buildInputs = [
    pkgs.vulkan-loader
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
    pkgs.libpng
    pkgs.libjpeg_turbo
    pkgs.libwebp
  ];

  # The upstream binary resolves libvulkan.so.1 with dlopen(),
  # so it does not appear in DT_NEEDED and autoPatchelf cannot
  # infer it from the ELF dependency table.
  runtimeDependencies = [
    pkgs.vulkan-loader
  ];

  dontConfigure = true;
  dontBuild = true;

  unpackPhase = ''
    runHook preUnpack

    mkdir source
    cd source
    unzip -q "$src"

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    binary="$(
      find . \
        -type f \
        -name waifu2x-ncnn-vulkan \
        -print \
        -quit
    )"

    if [ -z "$binary" ]; then
      echo "waifu2x-ncnn-vulkan executable not found in release archive" >&2
      exit 1
    fi

    install -Dm755 \
      "$binary" \
      "$out/libexec/waifu2x-ncnn-vulkan"

    makeWrapper \
      "$out/libexec/waifu2x-ncnn-vulkan" \
      "$out/bin/waifu2x-ncnn-vulkan" \
      --prefix LD_LIBRARY_PATH : "/run/opengl-driver/lib"

    mkdir -p \
      "$out/share/waifu2x-ncnn-vulkan"

    modelCount=0

    while IFS= read -r -d "" modelDir; do
      cp -a \
        "$modelDir" \
        "$out/share/waifu2x-ncnn-vulkan/"

      modelCount=$((modelCount + 1))
    done < <(
      find . \
        -type d \
        -name 'models-*' \
        -print0
    )

    if [ "$modelCount" -eq 0 ]; then
      echo "waifu2x model directories not found in release archive" >&2
      exit 1
    fi

    test -d \
      "$out/share/waifu2x-ncnn-vulkan/models-cunet"

    runHook postInstall
  '';

  meta = {
    description = "NCNN Vulkan implementation of waifu2x";
    homepage = "https://github.com/nihui/waifu2x-ncnn-vulkan";
    license = pkgs.lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "waifu2x-ncnn-vulkan";
  };
}
