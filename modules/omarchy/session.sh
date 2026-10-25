# alloy-omarchy-session: desktop mode when the Omarchy frontend is on.
#
# The first time, it does what Omarchy's installer does for a new user:
# seed $HOME from the shipped defaults (/etc/skel on Arch), then run
# `omarchy-provision-user --first-install`. Then it starts Hyprland through
# uwsm with the same command as Omarchy's own session file.

state="$HOME/.local/state/omarchy"
mkdir -p "$state"

if [[ ! -e "$state/.alloy-seeded" ]]; then
  echo "alloy: setting up Omarchy for $USER (first login)"
  alloy-omarchy-seed
  touch "$state/.alloy-seeded"
fi

if [[ ! -e "$state/done/finalize-user" ]]; then
  # Omarchy's own per-user setup: theme, xdg dirs, default apps, git, mise...
  # A failed step is logged and retried next login; it never blocks the desktop.
  if ! omarchy-provision-user --first-install; then
    echo "alloy: omarchy-provision-user failed; will retry at next login" >&2
    logger -t alloy-omarchy -- "omarchy-provision-user failed; will retry at next login" || true
  fi
fi

exec uwsm start -g -1 -e -D Hyprland hyprland.desktop
