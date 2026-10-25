# There is no bootloader: the PS5 loader payload reads bzImage, initrd.img and
# cmdline.txt straight off the FAT32 partition. nixos-rebuild hands each new
# generation to install-boot.sh, which writes those files.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.ps5;

  installBoot = pkgs.writeShellApplication {
    name = "alloy-install-boot";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
    ];
    runtimeEnv.ALLOY_VRAM = cfg.vram;
    text = builtins.readFile ./install-boot.sh;
  };
in
{
  boot.loader.external = {
    enable = true;
    installHook = lib.getExe installBoot;
  };

  system.build.alloyInstallBoot = installBoot;
}
