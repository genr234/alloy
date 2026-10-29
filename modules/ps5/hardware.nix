# PS5 hardware basics: filesystems, kernel parameters, firmware, GPU, fan.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.ps5;
  ps5_control = "${cfg.tools}/bin/ps5_control";
in
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/${cfg.label}";
    fsType = "ext4";
    autoResize = true;
  };

  fileSystems."/boot/efi" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  # Same parameters as ps5-linux-image's cmdline.txt (minus root=, which NixOS
  # takes from fileSystems).
  boot.kernelParams = [
    "console=ttyTitania0"
    "console=tty0"
    "mitigations=off"
    "idle=halt"
    "preempt=full"
    # USB never sleeps: the boot drive, controllers and dongles otherwise get
    # suspended (this kernel's default is 2 s), the most common cause of
    # disconnects and freezes in ps5-bazzite-deck's reports.
    "usbcore.autosuspend=-1"
  ]
  ++ lib.optional (cfg.videoMode != null) "video=DP-1:${cfg.videoMode}";

  hardware.enableRedistributableFirmware = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    package = lib.mkIf cfg.tuning.zen2 (
      pkgs.mesa.overrideAttrs (old: {
        env = (old.env or { }) // {
          NIX_CFLAGS_COMPILE = toString (old.env.NIX_CFLAGS_COMPILE or "") + " -march=znver2 -mtune=znver2";
        };
      })
    );
  };

  # The PS5 can't suspend or hibernate under Linux (ps5-linux FAQ): a
  # suspended console doesn't come back. This also makes Omarchy hide its
  # Suspend and Hibernate menu entries (omarchy-sleep-disabled checks this file).
  environment.etc."systemd/sleep.conf.d/omarchy-sleep-disabled.conf".text = ''
    [Sleep]
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  # Keep the Bluetooth chips (IW620 1286:2059, MediaTek 0e8d:3603) and the
  # Salina xHCI (104d:9108) out of runtime suspend, whatever the default
  # above: the chips drop off USB in U3 until a power-off, and the xHCI's
  # setup doesn't survive D3 (found by Dasloh, via ps5-bazzite-deck).
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1286", ATTR{idProduct}=="2059", TEST=="power/control", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0e8d", ATTR{idProduct}=="3603", TEST=="power/control", ATTR{power/control}="on"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x104d", ATTR{device}=="0x9108", TEST=="power/control", ATTR{power/control}="on"
  '';

  networking.networkmanager.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  zramSwap.enable = true;

  environment.systemPackages = [ cfg.tools ];

  # Fan control is always on, like upstream's ps5fan.service. Mode switches
  # only toggle boost; they never touch the fan.
  systemd.services.ps5-fan = {
    description = "PS5 fan control";
    wantedBy = [ "multi-user.target" ];
    after = [ "dev-icc.device" ];
    unitConfig.ConditionPathExists = "/dev/icc";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${ps5_control} --fan on";
      ExecStop = "${ps5_control} --fan off";
    };
  };
}
