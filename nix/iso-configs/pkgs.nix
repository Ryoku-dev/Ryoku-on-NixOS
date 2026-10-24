{ inputs, pkgs, ... }:

{
  # All the packages should be added in this file below.
  # Check https://search.nixos.org/packages to search for more packages.
  #
  # e.g:
  #
  # environment.systemPackages = with pkgs; [
  #   chromium
  #   nano
  #   git
  #   brave
  #   proton-vpn
  # ];

  environment.systemPackages = with pkgs; [
    # DEV
    neovim

    # CLI
    curl
    wget
    ncdu
    btop
    git

    # APPS
    gpu-screen-recorder-ui
    mission-center
    nwg-look

    # PACKAGES
    tumbler
    ffmpegthumbnailer
    ffmpeg-headless
    wlsunset
    uv
    unzip

    # LARP
    unimatrix
    cbonsai
    lavat
    fetch
  ];
}
