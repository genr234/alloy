# Installs a NixOS generation where the PS5 loader looks for it.
#
#   alloy-install-boot <system toplevel> [boot dir]
#
# Called by nixos-rebuild (boot.loader.external) with just the toplevel, in
# which case it writes to the mounted boot partition. The image builder calls it
# with a staging directory instead.
#
# The loader reads four files from the root of the FAT32 partition:
# bzImage, initrd.img, cmdline.txt (max 2047 chars) and vram.txt.
# There is no boot menu, so the previous generation is kept as *.old files.

toplevel="${1:?usage: alloy-install-boot <system toplevel> [boot dir]}"
boot="${2:-/boot/efi}"

if [[ $# -lt 2 ]] && ! mountpoint -q "$boot"; then
  echo "alloy: $boot is not mounted, not installing the kernel" >&2
  exit 1
fi

cmdline="init=$toplevel/init $(<"$toplevel/kernel-params")"
if ((${#cmdline} > 2047)); then
  echo "alloy: kernel command line is ${#cmdline} characters, the loader reads at most 2047" >&2
  exit 1
fi

current=""
if [[ -f "$boot/cmdline.txt" ]]; then
  current="$(<"$boot/cmdline.txt")"
fi

if [[ "$current" == "$cmdline" && -f "$boot/bzImage" && -f "$boot/initrd.img" ]]; then
  echo "alloy: boot partition already has this generation"
else
  # Stage everything first, so a full or yanked drive never leaves us
  # without a bootable kernel.
  install -m 0644 "$toplevel/kernel" "$boot/bzImage.new"
  install -m 0644 "$toplevel/initrd" "$boot/initrd.img.new"
  printf '%s\n' "$cmdline" >"$boot/cmdline.txt.new"

  if [[ -n "$current" ]]; then
    for f in bzImage initrd.img cmdline.txt; do
      if [[ -f "$boot/$f" ]]; then
        mv -f "$boot/$f" "$boot/$f.old"
      fi
    done
  fi
  for f in bzImage initrd.img cmdline.txt; do
    mv -f "$boot/$f.new" "$boot/$f"
  done
  echo "alloy: installed $(basename "$toplevel")"
fi

printf '%s\n' "$ALLOY_VRAM" >"$boot/vram.txt"

cat >"$boot/ROLLBACK.txt" <<'EOF'
alloy boot partition
===================

bzImage, initrd.img and cmdline.txt are the current NixOS generation.
They are rewritten by `nixos-rebuild switch` / `nixos-rebuild boot`.
Edit boot.kernelParams in the flake instead of cmdline.txt, or your change
will be lost on the next rebuild.

If the newest generation does not boot:
  1. Plug this drive into any computer.
  2. Rename bzImage.old, initrd.img.old and cmdline.txt.old
     to bzImage, initrd.img and cmdline.txt (replacing the new ones).
  3. Boot the PS5 again, then run `sudo nixos-rebuild switch --rollback`.

If it boots but something is broken, just run
`sudo nixos-rebuild switch --rollback`.
EOF

sync
