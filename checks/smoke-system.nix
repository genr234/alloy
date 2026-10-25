# Shared by every system in the boot test: the ps5 and vanilla modules with a
# stock kernel and QEMU disk drivers instead of the PS5's.
{ lib, pkgs, ... }:
{
  alloy.ps5.label = "alloy-smoke";
  # No session loop in the test VM; the test confirms boots by hand.
  alloy.vanilla.autoFallback = true;
  alloy.vanilla.flatpak = false; # needs the network
  alloy.vanilla.containers = false; # not under test, keeps the image small
  alloy.ps5.wifi.enable = false; # the driver targets the PS5 kernel

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_blk"
  ];
  boot.initrd.kernelModules = lib.mkForce [ ];
  boot.kernelParams = [
    "console=ttyS0" # last console= wins: logs go to the serial port
    "systemd.getty_auto=0" # no login prompt on ttyS0: it would hang up the self-test's output
  ];
  hardware.enableRedistributableFirmware = lib.mkForce false;

  system.stateVersion = "26.11";
}
