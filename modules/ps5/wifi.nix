# Built-in Wi-Fi on PS5 consoles with the Marvell/NXP IW620 chip
# (lspci: 1b4b:2b56). Upstream: github.com/ps5-linux/ps5-linux-mwifiex.
#
# The firmware is Sony's: the loader copies it out of PS5 OS onto the boot
# partition (lib/nxp/pcieuartiw620_combo_v1.bin) at every launch. It can't be
# shipped in the image, so a boot service copies it to /lib/firmware, where
# the kernel looks after NixOS's own firmware directory, then loads the driver
# with upstream's options. Consoles without the chip skip all of this.
#
# Wi-Fi settings for every chip come from ps5-bazzite-deck: the permanent MAC,
# and power saving kept off (Steam's developer toggle switches it back on, and
# with it the IW620 drops from ~700 to ~100 Mbit/s).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.alloy.ps5.wifi;
  fwName = "nxp/pcieuartiw620_combo_v1.bin";

  driver = config.boot.kernelPackages.callPackage ../../pkgs/ps5-iw620 {
    src = inputs.mwifiex-nxp;
    ps5Patches = inputs.ps5-mwifiex;
  };

  # From install.sh (MOAL_OPTIONS, with firmware auto-reset off as upstream).
  moalOptions = lib.concatStringsSep " " [
    "fw_name=${fwName}"
    "pcie_int_mode=1"
    "drv_mode=1"
    "cfg80211_wext=4"
    "sta_name=mlan"
    "ext_scan=1"
    "wifi_reset_config=0"
    "sched_scan=0"
    "ps_mode=2"
    "auto_ds=2"
    "amsdu_disable=1"
    "auto_fw_reload=0"
  ];

  # Power saving off on every Wi-Fi interface (wlan*, wlp*, the IW620's mlan*),
  # live with iw and in the connection profile with nmcli. Only acts when
  # something is on.
  powersave-off = pkgs.writeShellApplication {
    name = "alloy-wifi-powersave-off";
    runtimeInputs = [
      pkgs.iw
      config.networking.networkmanager.package
    ];
    text = ''
      for dev in /sys/class/net/*; do
        [ -d "$dev/wireless" ] || continue
        name=''${dev##*/}
        state=$(iw dev "$name" get power_save 2>/dev/null || true)
        if [[ "$state" == *": on"* ]]; then
          iw dev "$name" set power_save off && echo "Wi-Fi power saving switched off on $name"
        fi
        conn=$(nmcli -g GENERAL.CONNECTION device show "$name" 2>/dev/null || true)
        [ -n "$conn" ] || continue
        setting=$(nmcli -g 802-11-wireless.powersave connection show "$conn" 2>/dev/null || true)
        if [[ "$setting" != 2* ]]; then
          nmcli connection modify "$conn" 802-11-wireless.powersave 2 &&
            echo "Wi-Fi power saving off for the connection $conn"
        fi
      done
    '';
  };
in
{
  options.alloy.ps5.wifi = {
    enable = lib.mkEnableOption "the built-in Wi-Fi driver for consoles with the IW620 chip" // {
      default = true;
    };

    keepPowerSaveOff = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Switch Wi-Fi power saving off whenever a Wi-Fi interface comes up and
        every two minutes, on every chip. Steam's developer settings switch it
        back on, and with it the IW620 drops to about 100 Mbit/s.
      '';
    };
  };

  config = lib.mkMerge [
    {
      networking.networkmanager = {
        wifi = {
          # A random scan MAC changes the adapter address mid-scan, which makes
          # Wi-Fi joins (and Steam's first-start network step) fail.
          scanRandMacAddress = false;
          macAddress = "permanent";
        };
        # Ask DHCP by hardware address, not by the machine id, so a freshly
        # flashed image keeps its IP address.
        settings.connection."ipv4.dhcp-client-id" = "mac";
      };
    }

    (lib.mkIf cfg.keepPowerSaveOff {
      networking.networkmanager.wifi.powersave = false;
      networking.networkmanager.dispatcherScripts = [
        {
          type = "basic";
          source = pkgs.writeShellScript "alloy-wifi-powersave" ''
            [ "$2" = up ] && [ -d "/sys/class/net/$1/wireless" ] || exit 0
            exec ${lib.getExe powersave-off}
          '';
        }
      ];
      systemd.services.alloy-wifi-powersave = {
        description = "Keep Wi-Fi power saving off";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe powersave-off;
        };
      };
      systemd.timers.alloy-wifi-powersave = {
        description = "Keep Wi-Fi power saving off (Steam switches it back on)";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "2min";
        };
      };
    })

    (lib.mkIf cfg.enable {
      boot.extraModulePackages = [ driver ];
      boot.extraModprobeConfig = ''
        softdep moal pre: cfg80211 mlan
        options moal ${moalOptions}
      '';
      # Loaded by ps5-wifi.service once the firmware is in place, not by udev
      # at boot (when the boot partition isn't mounted yet).
      boot.blacklistedKernelModules = [ "moal" ];

      systemd.services.ps5-wifi = {
        description = "PS5 built-in Wi-Fi (IW620 firmware + driver)";
        wantedBy = [ "multi-user.target" ];
        before = [ "NetworkManager.service" ];
        unitConfig.RequiresMountsFor = "/boot/efi";
        path = [
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.kmod
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          found=""
          for dev in /sys/bus/pci/devices/*; do
            if [ "$(cat "$dev/vendor")" = 0x1b4b ] && [ "$(cat "$dev/device")" = 0x2b56 ]; then
              found=1
            fi
          done
          if [ -z "$found" ]; then
            echo "No IW620 Wi-Fi chip on this console; nothing to do."
            exit 0
          fi
          src=/boot/efi/lib/${fwName}
          if [ ! -f "$src" ]; then
            echo "Wi-Fi firmware not found at $src (the loader puts it there); skipping."
            exit 0
          fi
          install -Dm644 "$src" /lib/firmware/${fwName}
          modprobe moal
        '';
      };
    })
  ];
}
