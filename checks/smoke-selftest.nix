# The self-test of the boot test's first generation. It runs on two boots:
#
# Boot 1 (fresh image, first boot): image setup, boot hook, boot report. Then it
#   installs generation 2 as the new default (as nixos-rebuild would) and marks
#   generation 2's boot as never confirmed, i.e. it "failed".
#
# Boot 2 (the loader starts generation 2, from the new files on the FAT
#   partition): generation 2's initrd must notice the failed trial and kexec
#   into this generation (alloy.fallback=1). The test then plays a working
#   session, and alloy-boot-confirm must make this generation the default again.
{ gen2 }:
{
  lib,
  pkgs,
  config,
  ...
}:
{
  # Generation 2 travels in the image.
  alloy.ps5.image.extraStorePaths = [ gen2 ];

  systemd.services.alloy-selftest = {
    wantedBy = [ "multi-user.target" ];
    after = [
      "alloy-register-nix-paths.service"
      "growpart.service"
      "local-fs.target"
    ];
    path = [
      config.nix.package
      pkgs.util-linux
      pkgs.gnugrep
      pkgs.coreutils
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      exec > /dev/ttyS0 2>&1
      fail() { echo "ALLOY-SELFTEST-FAIL: $*"; systemctl --no-block poweroff; exit 1; }
      self=$(readlink -f /run/current-system)

      if grep -qw alloy.fallback=1 /proc/cmdline; then
        # ---------------- boot 2: we got here by falling back ----------------
        echo "selftest: boot 2, started by the picker's fallback"
        grep -qw alloy.picked=1 /proc/cmdline || fail "fallback boot without alloy.picked=1"
        [ "$(cat /var/lib/alloy/boot-trial)" = "$self" ] || fail "picker did not record this generation as the trial"

        # A working session, as the session loop would log it.
        logger -t alloy-session -- "starting desktop mode (logs: journalctl -t alloy-desktop)"
        sleep 22
        # What the alloy-boot-confirm timer runs (called directly: a blocking
        # systemctl start from inside the boot transaction can deadlock).
        ${config.systemd.services.alloy-boot-confirm.serviceConfig.ExecStart} \
          || fail "alloy-boot-confirm failed"

        [ ! -e /var/lib/alloy/boot-trial ] || fail "boot was not confirmed"
        [ "$(readlink -f /nix/var/nix/profiles/system)" = "$self" ] \
          || fail "fallback generation did not become the default profile"
        grep -q "init=$self/init" /boot/efi/cmdline.txt \
          || fail "boot partition does not point at the fallback generation"
        grep -q "${gen2}" /boot/efi/cmdline.txt.old \
          || fail "the failed generation is not kept as *.old"
        echo "ALLOY-SELFTEST-OK fallback to the previous generation worked and stuck"
        systemctl --no-block poweroff
        exit 0
      fi

      # ---------------- boot 1: fresh image ----------------
      [ -e /nix-path-registration ] && fail "store paths were not registered"
      nix-store --verify-path /run/current-system || fail "store database is missing the system"
      [ "$(readlink -f /nix/var/nix/profiles/system)" = "$self" ] \
        || fail "system profile was not created"

      # The root partition should now run to the end of the (bigger) disk,
      # and the filesystem should fill it.
      disk_bytes=$(lsblk -bndo SIZE /dev/vda)
      part_bytes=$(lsblk -bndo SIZE "$(findmnt -no SOURCE /)")
      root_bytes=$(findmnt -bno SIZE /)
      [ "$part_bytes" -gt $((disk_bytes - 600 * 1024 * 1024)) ] \
        || fail "root partition was not grown ($part_bytes of $disk_bytes bytes)"
      [ "$root_bytes" -gt $((part_bytes * 9 / 10)) ] \
        || fail "root filesystem was not grown ($root_bytes in a $part_bytes byte partition)"

      mountpoint -q /boot/efi || fail "/boot/efi is not mounted"
      for f in bzImage initrd.img cmdline.txt vram.txt; do
        [ -f /boot/efi/$f ] || fail "/boot/efi/$f missing"
      done
      grep -q "init=$self/init" /boot/efi/cmdline.txt \
        || fail "cmdline.txt does not point at the running system"

      # What nixos-rebuild does on every switch.
      ${config.system.build.installBootLoader} "$self" \
        | grep -q "already has this generation" || fail "boot hook did not recognise the running system"

      # The boot report: runs, saves to the boot partition, keeps the
      # previous boot's report.
      echo "selftest: boot report"
      # --no-block: a blocking systemctl call from a unit that is part of the
      # boot transaction can deadlock systemd.
      systemctl --no-block stop alloy-report.timer
      echo "boot: an-earlier-boot" > /boot/efi/alloy-report.txt
      timeout 300 /run/current-system/sw/bin/alloy-report > /tmp/report.out 2>&1 \
        || { cat /tmp/report.out; fail "alloy-report failed or hung"; }
      echo "selftest: boot report ran"
      grep -q '^\[ok\] kernel' /tmp/report.out || fail "report: kernel line missing"
      grep -q 'boot partition holds the generation that is running' /tmp/report.out \
        || fail "report: boot partition line missing"
      grep -qx "boot: $(cat /proc/sys/kernel/random/boot_id)" /boot/efi/alloy-report.txt \
        || fail "report was not saved to the boot partition"
      grep -qx 'boot: an-earlier-boot' /boot/efi/alloy-report.prev.txt \
        || fail "previous boot's report was not kept"
      timeout 300 /run/current-system/sw/bin/alloy-report --quiet || fail "second alloy-report run failed"
      grep -qx 'boot: an-earlier-boot' /boot/efi/alloy-report.prev.txt \
        || fail "a second run in the same boot replaced the previous boot's report"
      sed -n '1,/problem\|No problems/p' /tmp/report.out | sed 's/^/REPORT| /'

      # Install generation 2 as the default, like `nixos-rebuild switch` would,
      # and record that its boot "failed" (never confirmed).
      echo "selftest: installing generation 2"
      nix-env -p /nix/var/nix/profiles/system --set ${gen2} || fail "could not add generation 2"
      ${gen2}/bin/switch-to-configuration boot || fail "could not install generation 2's boot files"
      grep -q "init=${gen2}/init" /boot/efi/cmdline.txt || fail "boot files do not point at generation 2"
      mkdir -p /var/lib/alloy
      echo "${gen2}" > /var/lib/alloy/boot-trial
      sync

      echo "ALLOY-PHASE1-OK root=$root_bytes bytes, $(nix-store -q --requisites /run/current-system | wc -l) store paths registered"
      systemctl --no-block poweroff
    '';
  };
}
