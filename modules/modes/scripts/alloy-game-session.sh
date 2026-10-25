# Game mode: Steam Big Picture in gamescope, straight on the display.

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
mkdir -p "$state"
rm -f "$state/end-request"

# From ps5-linux-image's CachyOS session: gamescope takes the DRM and input
# devices through logind, and must not abort when no input device exists yet.
export ALLOY_MODE=game
export LIBSEAT_BACKEND=logind
export WLR_LIBINPUT_NO_DEVICES=1

read -r -a gamescope_args <<<"$ALLOY_GAMESCOPE_ARGS"
read -r -a steam_args <<<"$ALLOY_STEAM_ARGS"

finish() {
  rm -f "$state/game-active" "$state/end-request"
  if [[ "$ALLOY_PERFORMANCE" == 1 ]]; then
    systemctl stop alloy-game-performance.service || true
  fi
}
trap finish EXIT

if [[ "$ALLOY_PERFORMANCE" == 1 ]]; then
  systemctl start alloy-game-performance.service ||
    echo "alloy: could not switch on the performance profile" >&2
fi
touch "$state/game-active"

gamescope "${gamescope_args[@]}" -- steam "${steam_args[@]}" &
gamescope_pid=$!

# Steam's "Switch to Desktop" runs steamos-session-select inside Steam's
# sandbox, which can only leave a note in $state. Act on it from out here:
# ask Steam to quit (so cloud saves sync), then make sure gamescope is gone.
while kill -0 "$gamescope_pid" 2>/dev/null; do
  if [[ -e "$state/end-request" ]]; then
    rm -f "$state/end-request"
    timeout 20 steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 30); do
      kill -0 "$gamescope_pid" 2>/dev/null || break
      sleep 1
    done
    kill "$gamescope_pid" 2>/dev/null || true
  fi
  sleep 1
done

wait "$gamescope_pid" || true
