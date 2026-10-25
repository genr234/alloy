# Switch modes:  alloy-mode game | desktop | shell
#
# Records which mode the session loop should start next, then ends the
# current session.

usage() {
  echo "usage: alloy-mode game|desktop|shell" >&2
  echo "  game     Steam Big Picture" >&2
  echo "  desktop  Hyprland" >&2
  echo "  shell    leave to the TTY (run alloy-session to come back)" >&2
}

target="${1:-}"
case "$target" in
  game | desktop | shell) ;;
  *)
    usage
    exit 2
    ;;
esac

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
mkdir -p "$state"
printf '%s\n' "$target" >"$state/next-mode"

case "${ALLOY_MODE:-}" in
  desktop)
    hyprctl dispatch exit >/dev/null
    ;;
  game)
    touch "$state/end-request"
    ;;
  *)
    if [[ -e "$state/game-active" ]]; then
      # Called from somewhere that lost ALLOY_MODE (e.g. Steam's sandbox).
      touch "$state/end-request"
    else
      echo "alloy: not inside a alloy session; the next session starts in $target mode"
    fi
    ;;
esac
