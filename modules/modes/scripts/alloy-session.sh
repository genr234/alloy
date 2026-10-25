# The session loop, started on tty1 right after autologin.
#
# It runs one mode at a time. When that mode's session ends, it starts the mode
# that was requested with `alloy-mode`, or the default mode if nothing was.
# So quitting Steam in game mode, for any reason, lands you back on the desktop.
#
# Everything it says also goes to the journal (journalctl -t alloy-session), so
# the boot report can tell which modes ran and how they ended.

say() {
  echo "alloy: $*" >&2
  logger -t alloy-session -- "$*" 2>/dev/null || true
}

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
mkdir -p "$state"

# Every boot starts in the default mode, whatever was requested last time.
rm -f "$state/next-mode" "$state/end-request" "$state/game-active"

quick_exits=0
while true; do
  mode="$ALLOY_DEFAULT_MODE"
  if [[ -f "$state/next-mode" ]]; then
    mode="$(<"$state/next-mode")"
    rm -f "$state/next-mode"
  fi

  case "$mode" in
    desktop | game) ;;
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
  if ((quick_exits >= 3)); then
    say "sessions keep exiting right away; staying on the TTY."
    say "check 'journalctl -t alloy-desktop -t alloy-game', then run 'alloy-session'."
    exit 1
  fi
done
