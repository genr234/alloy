# Finish an update that changed the kernel, without a full reboot.
#
# `nixos-rebuild switch` applies everything else right away, and
# alloy-session moves to the new session scripts at the next mode switch. A
# running kernel can't be swapped, though, and a full reboot goes back
# through the PS5 loader. So this jumps into the new kernel with kexec
# instead: a few seconds, and the session comes back in the mode asked for.
#
#   alloy-update status         "restart" if the kernel changed (exit 0), else "current" (exit 1)
#   alloy-update finish [MODE]  kexec into the new system, then start MODE (default: desktop)
#   alloy-update notify         desktop notification with a Restart button, if a restart is needed
#
# Rest mode runs `finish rest` by itself, since nothing is open then.

booted="${ALLOY_BOOTED_SYSTEM:-/run/booted-system}"
current="${ALLOY_CURRENT_SYSTEM:-/run/current-system}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"

usage() {
  echo "usage: alloy-update status | finish [desktop|game|rest] | notify" >&2
}

# The kernel, its modules, the initrd or the kernel command line changed.
needs_restart() {
  local f
  for f in kernel initrd kernel-modules; do
    [[ "$(readlink -f "$booted/$f")" == "$(readlink -f "$current/$f")" ]] || return 0
  done
  [[ "$(cat "$booted/kernel-params" 2>/dev/null)" != "$(cat "$current/kernel-params" 2>/dev/null)" ]]
}

case "${1:-}" in
  status)
    if needs_restart; then
      echo restart
    else
      echo current
      exit 1
    fi
    ;;
  finish)
    mode="${2:-desktop}"
    case "$mode" in
      desktop | game | rest) ;;
      *)
        usage
        exit 2
        ;;
    esac
    if ! needs_restart; then
      echo "alloy: already running the newest kernel"
      exit 0
    fi
    # alloy-session reads this once at the next boot.
    mkdir -p "$state"
    echo "$mode" >"$state/boot-mode"
    if ! systemctl start alloy-kexec.service; then
      rm -f "$state/boot-mode"
      echo "alloy: couldn't start the new kernel; reboot to finish the update" >&2
      exit 1
    fi
    ;;
  notify)
    needs_restart || exit 0
    action=$(notify-send --app-name=Alloy --icon=system-reboot \
      --action=restart="Restart now" \
      "Update installed" \
      "Restart to finish it. It takes a few seconds; open apps close." \
      2>/dev/null) || exit 0
    if [[ "$action" == restart ]]; then
      exec alloy-update finish desktop
    fi
    ;;
  *)
    usage
    exit 2
    ;;
esac
