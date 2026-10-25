# system.build.ps5Image: a disk image laid out exactly like ps5-linux-image's,
# so the PS5 mounts the boot partition and the loader finds its files:
#
#   1 MiB .. 500 MiB   FAT32, label "boot"  (GPT partition 2, ESP)
#   500 MiB .. end     ext4, label <alloy.ps5.label>  (GPT partition 1)
#
# The root filesystem is as small as possible; on first boot it grows to fill
# the drive and the Nix store database is registered (as NixOS SD images do).
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.alloy.ps5;
  toplevel = config.system.build.toplevel;

  rootfs = pkgs.callPackage (modulesPath + "/../lib/make-ext4-fs.nix") {
    storePaths = [ toplevel ] ++ config.alloy.ps5.image.extraStorePaths;
    volumeLabel = cfg.label;
    populateImageCommands = ''
      mkdir -p ./files/boot/efi
    '';
  };

  bootFiles = pkgs.runCommand "alloy-boot-files" { } ''
    mkdir $out
    ${lib.getExe config.system.build.alloyInstallBoot} ${toplevel} $out
  '';

  image =
    pkgs.runCommand "${cfg.label}-ps5-image"
      {
        nativeBuildInputs = with pkgs; [
          util-linux
          dosfstools
          mtools
        ];
        passthru = { inherit rootfs bootFiles; };
      }
      ''
        mkdir -p $out
        img=$out/${cfg.label}.img

        # Sizes in 512-byte sectors.
        espStart=2048          # 1 MiB
        espSize=1021952        # 499 MiB
        rootStart=1024000      # 500 MiB
        rootSize=$(( ($(stat -c %s ${rootfs}) + 511) / 512 ))
        total=$(( rootStart + rootSize + 2048 ))  # + space for the backup GPT

        truncate -s $(( total * 512 )) "$img"
        sfdisk --no-reread --no-tell-kernel "$img" <<EOF
        label: gpt
        label-id: 6D796F73-0000-4000-8000-000000000000
        start=$rootStart, size=$rootSize, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, uuid=6D796F73-0000-4000-8000-000000000001, name="${cfg.label}"
        start=$espStart, size=$espSize, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, uuid=6D796F73-0000-4000-8000-000000000002, name="boot"
        EOF

        truncate -s $(( espSize * 512 )) esp.img
        mkfs.vfat -F 32 -n boot -i 6d796f73 esp.img
        # Store files are dated 1970, which FAT can't represent.
        cp -r ${bootFiles} bootfiles
        chmod -R u+w bootfiles
        touch -d "1980-01-02 00:00:00" bootfiles/*
        mcopy -psvm -i esp.img bootfiles/* ::/

        dd if=esp.img of="$img" bs=512 seek=$espStart conv=notrunc,sparse status=none
        dd if=${rootfs} of="$img" bs=1M seek=$(( rootStart / 2048 )) conv=notrunc,sparse status=none

        sfdisk --dump "$img"
      '';
in
{
  options.alloy.ps5.image.extraStorePaths = lib.mkOption {
    type = lib.types.listOf lib.types.package;
    default = [ ];
    internal = true;
    description = "More store paths to put in the image (the boot test uses it for a second generation).";
  };

  config = {
    system.build.ps5Image = image;

    # First boot: register the store paths that were copied into the image and
    # create the system profile, so nixos-rebuild and rollbacks work.
    systemd.services.alloy-register-nix-paths = {
      description = "Register Nix store paths from the PS5 image";
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix-path-registration";
      };
      wantedBy = [ "sysinit.target" ];
      before = [
        "sysinit.target"
        "shutdown.target"
        "nix-daemon.socket"
        "nix-daemon.service"
      ];
      after = [ "local-fs.target" ];
      conflicts = [ "shutdown.target" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${lib.getExe' config.nix.package.out "nix-store"} --load-db < /nix-path-registration
        touch /etc/NIXOS
        ${lib.getExe' config.nix.package.out "nix-env"} -p /nix/var/nix/profiles/system --set /run/current-system
        rm -f /nix-path-registration
      '';
    };

    # Grow the root partition and filesystem to the size of the drive.
    boot.growPartition = true;
  };
}
