# Built-in Bluetooth: DualSense pairing that sticks, controllers that
# reconnect by themselves, and the PS5's Bluetooth chips kept awake.
# From ps5-bazzite-deck (VivaLaVent), which took the BlueZ settings from the
# ps5-cachyos-setup project's packet traces.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  btmgmt = "${config.hardware.bluetooth.package}/bin/btmgmt";
in
{
  hardware.bluetooth = {
    enable = true;
    settings.General = {
      # A DualSense pairs again ~1.5 s after pairing to upgrade its link key;
      # BlueZ's default rejects that round and deletes the bond.
      JustWorksRepairing = "always";
      # With pairable off when the pad asks, BlueZ answers "No Bonding" and
      # the bond is thrown away.
      PairableTimeout = 0;
    };
  };

  # hidp otherwise loads on the first controller connection, which can then
  # drop once.
  boot.kernelModules = [ "hidp" ];
  # The PS5's Bluetooth chips drop off USB once their port is suspended and
  # only come back after a power-off.
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
  '';

  services.udev.extraRules = ''
    # MediaTek Bluetooth (PS5 Slim, 0e8d:3603): interfaces 3 and 4 are a second,
    # phantom controller that keeps the real one from working.
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="3603", ATTR{bInterfaceNumber}=="03", ATTR{authorized}="0"
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="0e8d", ATTRS{idProduct}=="3603", ATTR{bInterfaceNumber}=="04", ATTR{authorized}="0"

    # Make the adapter connectable again whenever it (re)appears.
    ACTION=="add", SUBSYSTEM=="bluetooth", KERNEL=="hci0", TAG+="systemd", ENV{SYSTEMD_WANTS}+="ps5-bt-connectable.service"
  '';

  # The adapter comes up non-connectable, so a paired controller can't
  # reconnect by pressing its PS button. Runs after every bluetoothd start
  # (wantedBy + partOf) and whenever hci0 appears (udev rule above).
  systemd.services.ps5-bt-connectable = {
    description = "Bluetooth adapter accepts incoming connections";
    wantedBy = [ "bluetooth.service" ];
    after = [ "bluetooth.service" ];
    partOf = [ "bluetooth.service" ];
    serviceConfig.Type = "oneshot";
    # bluetoothd sets the adapter's modes once it has started: wait for that.
    # Without bluetoothd there is nothing to do; its start runs this again.
    script = ''
      ${config.systemd.package}/bin/systemctl is-active -q bluetooth.service || exit 0
      sleep 3
      ${btmgmt} --index 0 connectable on
    '';
  };
}
