# Running from the internal M.2 SSD instead of the USB drive.
#
# As with ps5-linux-image, the USB drive stays: the loader still reads the
# kernel, initrd and command line from its FAT32 partition, but the root
# filesystem lives on the M.2 (ext4, label "<label>-m2").
#
#   1. On PS5 OS, format the M.2 under Settings > Storage > M.2 SSD Storage.
#   2. Boot alloy from USB and run:   sudo alloy-m2-install <flake>#ps5-m2
#      (the flake's ps5-m2 configuration is ps5 with alloy.ps5.root = "m2")
#   3. From then on, rebuild with  --flake <flake>#ps5-m2
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.ps5;
  m2Label = "${cfg.label}-m2";

  installer = pkgs.writeShellApplication {
    name = "alloy-m2-install";
    runtimeInputs = with pkgs; [
      coreutils
      util-linux
      e2fsprogs
      config.nix.package
      config.system.build.nixos-install
      cfg.tools
    ];
    runtimeEnv = {
      ALLOY_M2_LABEL = m2Label;
      ALLOY_INSTALL_BOOT = lib.getExe config.system.build.alloyInstallBoot;
    };
    text = builtins.readFile ./m2-install.sh;
  };
in
{
  options.alloy.ps5.root = lib.mkOption {
    type = lib.types.enum [
      "usb"
      "m2"
    ];
    default = "usb";
    description = ''
      Where the root filesystem lives. "m2" uses the internal M.2 SSD
      (label <label>-m2); the boot files stay on the USB drive either way.
    '';
  };

  config = lib.mkMerge [
    { environment.systemPackages = [ installer ]; }
    (lib.mkIf (cfg.root == "m2") {
      fileSystems."/".device = lib.mkForce "/dev/disk/by-label/${m2Label}";
      boot.initrd.availableKernelModules = [ "nvme" ];
    })
  ];
}
