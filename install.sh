#!/usr/bin/env bash
# Flash alloy onto a USB drive for the PS5, from Linux or macOS:
#
#   curl -fsSL https://raw.githubusercontent.com/genr234/alloy/main/install.sh | bash
#
# Downloads the latest release image (alloy.img.zst), checks it against the
# release's SHA256SUMS, asks which external drive to use and writes it there.
# The drive is ERASED. Options go after `bash -s --`:
#
#   --image FILE   flash a local alloy.img or alloy.img.zst instead
#   --build        build the image with Nix (pulls from the alloy cache)
#   --release TAG  a specific release instead of the latest
#   --device DEV   skip the drive menu (it still asks before erasing)
#
# ALLOY_REPO=owner/repo flashes someone else's fork.
set -euo pipefail

repo="${ALLOY_REPO:-genr234/alloy}"
image=""
parts=()
build=""
release=""
device=""

say() { printf '\033[1malloy:\033[0m %s\n' "$*" >&2; }
die() {
  say "$*"
  exit 1
}
need() { command -v "$1" >/dev/null || die "$1 is missing. $2"; }
usage() {
  cat >&2 <<'EOF'
usage: install.sh [--image FILE | --build] [--release TAG] [--device DEV]
  --image FILE   flash a local alloy.img or alloy.img.zst
  --build        build the image with Nix instead of downloading a release
  --release TAG  a specific release instead of the latest
  --device DEV   skip the drive menu (it still asks before erasing)
EOF
}

# stdin is this script when it's piped into bash, so questions go to the TTY.
ask() {
  local answer
  [[ -r /dev/tty ]] || die "no terminal to ask on; pass --device and run it interactively"
  read -r -p "$1" answer </dev/tty
  printf '%s' "$answer"
}

while (($#)); do
  case "$1" in
    --image) image="${2:?--image needs a file}"; shift 2 ;;
    --build) build=1; shift ;;
    --release) release="${2:?--release needs a tag}"; shift 2 ;;
    --device) device="${2:?--device needs a disk}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option $1 (try --help)" ;;
  esac
done

os="$(uname -s)"
case "$os" in
  Linux | Darwin) ;;
  *) die "this installer runs on Linux or macOS; on Windows, flash the release's alloy.img.zst with Rufus or balenaEtcher" ;;
esac

if [[ $os == Darwin ]]; then
  zstd_hint="Install it with: brew install zstd"
else
  zstd_hint="Install it with your package manager (apt/dnf/pacman install zstd)."
fi

sha256() {
  if command -v sha256sum >/dev/null; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

work="${XDG_CACHE_HOME:-$HOME/.cache}/alloy-installer"
mkdir -p "$work"

# --- 1. The image -----------------------------------------------------------

if [[ -n $build ]]; then
  need nix "Install Nix (https://nixos.org/download) or drop --build to download a release."
  say "building $repo#image (the kernel comes from the alloy cache when CI has pushed it)..."
  # The cache options only take effect for trusted Nix users; otherwise the
  # kernel is compiled locally (about an hour).
  out="$(nix --extra-experimental-features 'nix-command flakes' build --no-link --print-out-paths \
    --option extra-substituters https://alloy.cachix.org \
    --option extra-trusted-public-keys alloy.cachix.org-1:/daEZJTQBuT6WYzOH6Bm5gqe/Y7TIw1giQ+gSEiiBGk= \
    "github:$repo#image")"
  image="$(echo "$out"/*.img)"
elif [[ -z $image ]]; then
  need curl ""
  if [[ -n $release ]]; then
    base="https://github.com/$repo/releases/download/$release"
  else
    base="https://github.com/$repo/releases/latest/download"
  fi
  say "fetching the checksum list from ${release:-the latest release}..."
  curl -fsSL "$base/SHA256SUMS" -o "$work/SHA256SUMS" ||
    die "no release found at $base. Make one (push a v* tag, or run the Release workflow), or use --build."
  # One line per file: the image, or its numbered parts (alloy.img.zst.part00,
  # ...) when it's over GitHub's 2 GiB limit for a release file.
  parts=()
  while read -r want file; do
    file="${file#./}"
    parts+=("$work/$file")
    if [[ -f $work/$file ]] && [[ "$(sha256 "$work/$file")" == "$want" ]]; then
      say "already downloaded $file"
      continue
    fi
    say "downloading $file..."
    curl -fL --progress-bar "$base/$file" -o "$work/$file.download"
    mv "$work/$file.download" "$work/$file"
    say "checking $file..."
    [[ "$(sha256 "$work/$file")" == "$want" ]] || {
      rm -f "$work/$file"
      die "checksum mismatch for $file; run the installer again"
    }
  done <"$work/SHA256SUMS"
  ((${#parts[@]})) || die "the release's SHA256SUMS lists no files"
  first="${parts[0]}"
  image="${first%.part[0-9][0-9]}"
fi

((${#parts[@]})) || parts=("$image") # --image and --build give one file
for f in "${parts[@]}"; do
  [[ -f $f ]] || die "image not found: $f"
done
case "$image" in
  *.zst) need zstd "$zstd_hint" ;;
esac

# The image as one stream: the parts joined, then decompressed.
read_image() {
  case "$image" in
    *.zst) cat "${parts[@]}" | zstd -dc ;;
    *) cat "${parts[@]}" ;;
  esac
}

# --- 2. The drive -------------------------------------------------------------

# One line per candidate drive: "<device>\t<description>". Only external /
# removable disks are offered, and never the one the running system is on.
list_drives() {
  if [[ $os == Darwin ]]; then
    diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk/ {print $1}' | while read -r d; do
      info="$(diskutil info "$d")"
      size="$(awk -F': *' '/Disk Size/ {sub(/ \(.*/, "", $2); print $2; exit}' <<<"$info")"
      name="$(awk -F': *' '/Media Name/ {print $2; exit}' <<<"$info")"
      printf '%s\t%s  %s\n' "$d" "$size" "$name"
    done
  else
    local rootdisk
    rootdisk="$(lsblk -npso NAME,TYPE "$(findmnt -nvo SOURCE /)" 2>/dev/null | awk '$2 == "disk" {print $1}' | tail -1)"
    # -P prints NAME="..." pairs, so empty columns (no TRAN, no MODEL) don't
    # shift the others.
    lsblk -dnpPo NAME,TYPE,RM,TRAN,SIZE,MODEL | while read -r line; do
      local NAME="" TYPE="" RM="" TRAN="" SIZE="" MODEL=""
      eval "$line"
      [[ $TYPE == disk && $NAME != "$rootdisk" ]] || continue
      [[ $RM == 1 || $TRAN == usb ]] || continue
      printf '%s\t%s  %s\n' "$NAME" "$SIZE" "$MODEL"
    done
  fi
}

if [[ -z $device ]]; then
  drives=()
  while IFS= read -r line; do drives+=("$line"); done < <(list_drives) # no mapfile in macOS's bash 3.2
  ((${#drives[@]})) || die "no USB drive found. Plug one in (it will be erased) and run the installer again."
  say "drives that can be erased:"
  for i in "${!drives[@]}"; do
    printf '  %d) %s\n' $((i + 1)) "${drives[$i]/$'\t'/   }" >&2
  done
  pick="$(ask "Which one? [1-${#drives[@]}] ")"
  if ! [[ $pick =~ ^[0-9]+$ ]] || ((pick < 1 || pick > ${#drives[@]})); then
    die "no drive picked, nothing written"
  fi
  device="${drives[$((pick - 1))]%%$'\t'*}"
fi

[[ -e $device ]] || die "$device does not exist"
say "this ERASES everything on $device and writes $(basename "$image") to it."
answer="$(ask "Type the device name ($device) to continue: ")"
[[ $answer == "$device" ]] || die "cancelled, nothing written"

# --- 3. Write it ---------------------------------------------------------------

sudo -v -p "alloy: password for sudo (to write to $device): "

target="$device"
if [[ $os == Darwin ]]; then
  diskutil unmountDisk "$device" >/dev/null
  target="${device/\/dev\/disk//dev/rdisk}" # the raw device is much faster
  bs=4m
else
  lsblk -nrpo NAME,MOUNTPOINT "$device" | awk '$2 != "" {print $1}' | while read -r part; do
    sudo umount "$part"
  done
  bs=4M
fi

progress=()
if dd if=/dev/zero of=/dev/null count=0 status=progress 2>/dev/null; then
  progress=(status=progress)
fi

say "writing (this takes a few minutes)..."
read_image | sudo dd of="$target" bs="$bs" "${progress[@]}"
sync

if [[ $os == Darwin ]]; then
  diskutil eject "$device" >/dev/null || true
fi

say "done. Plug the drive into the PS5 and start the ps5-linux loader."
say "first login: the user and initialPassword in hosts/ps5 (they're public: run passwd)."
