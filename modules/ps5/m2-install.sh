# alloy-m2-install: put alloy on the PS5's internal M.2 SSD.
#
#   sudo alloy-m2-install <flake>#ps5-m2
#
# The M.2 must have been formatted by PS5 OS first (Settings > Storage >
# M.2 SSD Storage). This ERASES it: m2_init writes the partition layout PS5 OS
# accepts, partition 1 becomes ext4 (label $ALLOY_M2_LABEL), and the flake's
# ps5-m2 system is installed onto it. The USB drive keeps the boot files; the
# current USB system stays bootable as the *.old fallback.

if ((EUID != 0)); then
  echo "Run as root: sudo alloy-m2-install <flake>#ps5-m2" >&2
  exit 1
fi
if [[ $# -ne 1 || $1 != *#* ]]; then
  echo "usage: alloy-m2-install <flake>#<configuration>   e.g. github:you/alloy#ps5-m2" >&2
  exit 2
fi
flake="${1%#*}"
name="${1##*#}"
disk=/dev/nvme0n1
part=/dev/nvme0n1p1
mnt=/mnt/alloy-m2

[[ -b $disk ]] || {
  echo "No M.2 SSD found ($disk)." >&2
  exit 1
}

echo "This ERASES everything on the M.2 SSD ($disk) and installs $name from $flake on it."
read -r -p "Type ERASE to continue: " answer
[[ $answer == ERASE ]] || {
  echo "Cancelled."
  exit 1
}

echo "Building $name..."
system=$(nix build --no-link --print-out-paths "$flake#nixosConfigurations.$name.config.system.build.toplevel")

echo "Writing the PS5-compatible partition layout..."
m2_init
udevadm settle
for _ in $(seq 20); do
  [[ -b $part ]] && break
  sleep 1
done
[[ -b $part ]] || {
  echo "$part did not appear after m2_init." >&2
  exit 1
}

echo "Formatting $part as ext4 ($ALLOY_M2_LABEL)..."
umount -q "$part" 2>/dev/null || true
mkfs.ext4 -F -L "$ALLOY_M2_LABEL" "$part"
mkdir -p "$mnt"
mount "$part" "$mnt"
trap 'umount -R "$mnt" 2>/dev/null || true' EXIT

echo "Installing $system..."
nixos-install --root "$mnt" --system "$system" --no-bootloader --no-root-passwd --no-channel-copy

echo "Pointing the USB drive's boot files at the M.2 system..."
"$ALLOY_INSTALL_BOOT" "$system"

cat <<EOF

Done. Next launch of the loader starts alloy from the M.2.
  - Your home folder on the M.2 starts fresh.
  - The USB system is kept as bzImage.old / initrd.img.old / cmdline.txt.old
    on the USB drive's boot partition (see ROLLBACK.txt there).
  - Rebuild from now on with:  nixos-rebuild switch --flake $flake#$name
EOF
