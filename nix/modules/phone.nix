{ ryokuNixpkgs }:
{ config, lib, ... }:
let
  cfg = config.programs.ryoku.phone;
in
{
  options.programs.ryoku.phone = {
    enable = lib.mkEnableOption "Ryoku phone integration";
    webcam.enable = lib.mkEnableOption "the phone camera through v4l2loopback";
  };

  config = lib.mkIf config.programs.ryoku.enable (lib.mkMerge [
    {
      environment.etc."ryoku/phone.json".text = builtins.toJSON {
        enabled = cfg.enable;
        webcam = cfg.enable && cfg.webcam.enable;
      };
      assertions = [ {
        assertion = !cfg.webcam.enable || cfg.enable;
        message = "programs.ryoku.phone.webcam.enable requires programs.ryoku.phone.enable";
      } ];
    }
    (lib.mkIf cfg.enable {
      programs.kdeconnect = {
        enable = true;
        package = ryokuNixpkgs.kdePackages.kdeconnect-kde;
      };
      services.udev.packages = [ ryokuNixpkgs.android-udev-rules ];
      services.avahi.enable = lib.mkDefault true;
      environment.systemPackages = [
        ryokuNixpkgs.scrcpy
        ryokuNixpkgs.android-tools
        ryokuNixpkgs.avahi
        ryokuNixpkgs.qt6.qttools
      ];
    })
    (lib.mkIf (cfg.enable && cfg.webcam.enable) {
      boot.extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
      boot.kernelModules = [ "v4l2loopback" ];
      boot.extraModprobeConfig = ''
        options v4l2loopback devices=1 video_nr=10 card_label="Ryoku Phone" exclusive_caps=1
      '';
    })
  ]);
}
