# alloy-report: writes the Phase 0 test results to the boot partition 90 s after
# boot and every 5 minutes after, so they can be read on any computer even when
# the screen stays black. Also runnable by hand: `sudo alloy-report`.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.ps5.report;

  report = pkgs.writeShellApplication {
    name = "alloy-report";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gnugrep
      gnused
      util-linux
      procps
      iproute2
      networkmanager
      config.systemd.package
    ];
    runtimeEnv.ALLOY_KERNEL_VERSION = config.boot.kernelPackages.kernel.modDirVersion;
    text = builtins.readFile ./report.sh;
  };
in
{
  options.alloy.ps5.report.enable =
    lib.mkEnableOption "the boot report written to the boot partition (alloy-report.txt)"
    // {
      default = true;
    };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ report ];

    systemd.services.alloy-report = {
      description = "Write alloy-report.txt to the boot partition";
      unitConfig.RequiresMountsFor = "/boot/efi";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe report} --quiet";
      };
    };

    systemd.timers.alloy-report = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "90s";
        OnUnitActiveSec = "5min";
      };
    };

    # Keep the journal across boots, so a report written after a forced
    # power-off can still show what happened before it.
    services.journald.settings.Journal.Storage = "persistent";
  };
}
