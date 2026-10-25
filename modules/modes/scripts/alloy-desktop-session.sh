# Desktop mode: Hyprland (plain, or Omarchy's).

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
mkdir -p "$state"
rm -f "$state/end-request"

# If game mode crashed, make sure the boost profile is off again.
if [[ "$ALLOY_PERFORMANCE" == 1 ]]; then
  systemctl stop alloy-game-performance.service 2>/dev/null || true
fi

export ALLOY_MODE=desktop
export LIBSEAT_BACKEND=logind

# start-hyprland by default; alloy-omarchy-session when the Omarchy frontend is on.
read -r -a desktop_command <<<"$ALLOY_DESKTOP_COMMAND"
exec "${desktop_command[@]}"
