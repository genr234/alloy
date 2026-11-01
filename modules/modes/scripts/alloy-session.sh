# The session loop, started on tty1 right after autologin.
#
# It runs one mode at a time. When that mode's session ends, it starts the mode
# that was requested with `alloy-mode`, or the default mode if nothing was.
# So quitting Steam in game mode, for any reason, lands you back on the desktop.
#
# After `nixos-rebuild switch`, it hands over to the new system's
# alloy-session between two modes, so new session scripts apply without a
# reboot (alloy-update covers kernel changes).
#
# Everything it says also goes to the journal (journalctl -t alloy-session), so
# the boot report can tell which modes ran and how they ended.

say() {
  echo "alloy: $*" >&2
  logger -t alloy-session -- "$*" 2>/dev/null || true
}

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
mkdir -p "$state"

system="${ALLOY_CURRENT_SYSTEM:-/run/current-system}"
running="$(readlink -m "$system")"

if [[ "${1:-}" != --reload ]]; then
  # Every boot starts in the default mode, whatever was requested last time.
  rm -f "$state/next-mode" "$state/end-request" "$state/game-active" "$state/rest-active"
  # Unless `alloy-update finish` just restarted into a new kernel and asked
  # for a mode. Only a fresh request counts: one left by a kexec that never
  # happened mustn't take over a later boot.
  if [[ -f "$state/boot-mode" ]] &&
    (($(date +%s) - $(stat -c %Y "$state/boot-mode") < 600)); then
    mv "$state/boot-mode" "$state/next-mode"
  fi
  rm -f "$state/boot-mode"
fi

quick_exits=0
while true; do
  if [[ "$(readlink -m "$system")" != "$running" && -x "$system/sw/bin/alloy-session" ]]; then
    say "the system was updated; continuing with its session scripts"
    exec "$system/sw/bin/alloy-session" --reload
  fi

  mode="$ALLOY_DEFAULT_MODE"
  if [[ -f "$state/next-mode" ]]; then
    mode="$(<"$state/next-mode")"
    rm -f "$state/next-mode"
  fi

  case "$mode" in
    desktop | game | rest) ;;
    shell)
      say "back on the TTY. Run 'alloy-session' to start the desktop again."
      exit 0
      ;;
    *)
      say "unknown mode '$mode', starting $ALLOY_DEFAULT_MODE"
      mode="$ALLOY_DEFAULT_MODE"
      ;;
  esac

  say "starting $mode mode (logs: journalctl -t alloy-$mode)"
  started=$SECONDS
  status=0
  systemd-cat --identifier="alloy-$mode" "alloy-$mode-session" || status=$?
  say "$mode mode ended after $((SECONDS - started))s with status $status"

  # Don't spin forever if a session can't start (e.g. no display).
  if ((SECONDS - started < ${ALLOY_QUICK_EXIT_SECONDS:-15})); then
    quick_exits=$((quick_exits + 1))
  else
    quick_exits=0
  fi
  # A game or rest session that can't start (Steam broken, no display) falls
  # back to the desktop, even when game mode is the default.
  if ((quick_exits > 0)) && [[ "$mode" != desktop && ! -f "$state/next-mode" ]]; then
    say "$mode mode exited right away; falling back to the desktop"
    echo desktop >"$state/next-mode"
  fi
  if ((quick_exits >= 3)); then
    say "sessions keep exiting right away; staying on the TTY."
    say "check 'journalctl -t alloy-desktop -t alloy-game -t alloy-rest', then run 'alloy-session'."
    exit 1
  fi
done
