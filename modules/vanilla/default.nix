# The VanillaOS layer: a system that's hard to break and easy to undo.
# Nix already gives a read-only store and generations; this adds:
#
#   - a boot-time generation picker (the PS5 loader can only boot the newest)
#   - automatic fallback to the previous generation when a new one never
#     reaches a working desktop, made permanent once the fallback works
#   - containers for other distros' apps (distrobox on Podman, like apx)
#   - Flatpak with Flathub as an app store
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.vanilla;
  confirm = cfg.autoFallback;

  picker = pkgs.writeShellApplication {
    name = "alloy-picker";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
      gnused
      kexec-tools
    ];
    runtimeEnv.ALLOY_TRIAL = if confirm then "1" else "0";
    text = builtins.readFile ./picker.sh;
  };

  boot-confirm = pkgs.writeShellApplication {
    name = "alloy-boot-confirm";
    runtimeInputs = with pkgs; [
      coreutils
      gnugrep
      util-linux
      config.systemd.package
      config.nix.package
    ];
    text = builtins.readFile ./confirm.sh;
  };
in
{
  options.alloy.vanilla = {
    generationPicker = lib.mkEnableOption "the boot-time generation picker (kexec)" // {
      default = true;
    };

    autoFallback = lib.mkOption {
      type = lib.types.bool;
      default = config.alloy.modes.enable or false;
      defaultText = lib.literalExpression "config.alloy.modes.enable";
      description = ''
        Boot the previous generation automatically when the last boot of the
        newest one never got desktop or game mode running, and keep it as the
        default once it works. Needs the alloy session (it decides what
        "working" means).
      '';
    };

    containers = lib.mkEnableOption "distrobox on Podman, to run other distros' apps" // {
      default = true;
    };

    flatpak = lib.mkEnableOption "Flatpak with the Flathub remote" // {
      default = true;
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.generationPicker {
      # The initrd gets the listed paths and their libraries, not the full Nix
      # closure, so every tool the picker calls is listed.
      boot.initrd.systemd.storePaths = [
        picker
        pkgs.bash
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnused
        pkgs.kexec-tools
      ];
      boot.initrd.systemd.services.alloy-picker = {
        description = "alloy generation picker";
        # After the root filesystem (and the store) are mounted under /sysroot,
        # before the switch to the chosen system.
        after = [ "initrd-fs.target" ];
        before = [ "initrd.target" ];
        wantedBy = [ "initrd.target" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe picker;
          StandardInput = "tty-force";
          StandardOutput = "tty";
          StandardError = "journal+console";
          TTYPath = "/dev/console";
        };
      };
    })

    (lib.mkIf (cfg.generationPicker && confirm) {
      systemd.services.alloy-boot-confirm = {
        description = "Confirm that this boot reached a working session";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe boot-confirm;
        };
      };
      systemd.timers.alloy-boot-confirm = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "15s";
        };
      };
    })

    (lib.mkIf cfg.containers {
      virtualisation.podman.enable = true;
      environment.systemPackages = [ pkgs.distrobox ];
    })

    (lib.mkIf cfg.flatpak {
      services.flatpak.enable = true;
      systemd.services.alloy-flathub = {
        description = "Add the Flathub remote to Flatpak";
        wantedBy = [ "multi-user.target" ];
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
        path = [ pkgs.flatpak ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        '';
      };
    })
  ];
}
