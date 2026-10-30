# Everything that makes NixOS run on a PS5. Nothing in here is about taste;
# that lives in modules/modes, hosts/ and home/.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  imports = [
    ./kernel.nix
    ./boot.nix
    ./image.nix
    ./report.nix
    ./wifi.nix
    ./bluetooth.nix
    ./m2.nix
    ./hardware.nix
  ];

  options.alloy.ps5 = {
    label = mkOption {
      type = types.strMatching "[a-zA-Z0-9_-]{1,16}";
      default = "alloy";
      description = ''
        Filesystem label of the ext4 root partition (max 16 characters).
        Also used as the image file name.
      '';
    };

    vram = mkOption {
      type = types.strMatching "0x[0-9a-fA-F]+";
      default = "0x20000000";
      description = ''
        Written to vram.txt on the boot partition and read by the loader.
        The default (512 MiB) enables dynamic VRAM allocation.
      '';
    };

    videoMode = mkOption {
      type = types.nullOr types.str;
      default = "1920x1080@60";
      example = null;
      description = ''
        Forced mode for the PS5's internal DP connector (video=DP-1:...).
        Some monitors only show a picture without it: set to null.
      '';
    };

    tuning.zen2 = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Build the kernel and Mesa for the PS5's Zen 2 CPU (-march=znver2), as
        CachyOS does for its optimized repos. Both then come from your own
        cache instead of NixOS's, so turn it on once CI builds them, and keep
        it only if it measurably helps on the console.
      '';
    };

    tools = mkOption {
      type = types.package;
      default = pkgs.callPackage ../../pkgs/ps5-tools.nix { src = inputs.ps5-tools; };
      defaultText = lib.literalExpression "ps5-linux-tools";
      description = "Package providing ps5_control (fan and boost).";
    };
  };
}
