# Game mode: Steam Big Picture in gamescope, straight on the display.

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
mkdir -p "$state"
rm -f "$state/end-request" "$state/steam-shutdown" "$state/steam-reboot"

# From ps5-linux-image's CachyOS session: gamescope takes the DRM and input
# devices through logind, and must not abort when no input device exists yet.
export ALLOY_MODE=game
export LIBSEAT_BACKEND=logind
export WLR_LIBINPUT_NO_DEVICES=1

# Steam's Power menu leaves these behind instead of shutting down itself
# (as in SteamOS's gamescope-session); we act on them once Steam is gone.
export STEAMOS_STEAM_SHUTDOWN_SENTINEL="$state/steam-shutdown"
export STEAMOS_STEAM_REBOOT_SENTINEL="$state/steam-reboot"

read -r -a gamescope_args <<<"$ALLOY_GAMESCOPE_ARGS"
read -r -a steam_args <<<"$ALLOY_STEAM_ARGS"

watcher_pid=
finish() {
  [[ -z "$watcher_pid" ]] || kill "$watcher_pid" 2>/dev/null || true
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
enable_decky
touch "$state/game-active"

gamescope "${gamescope_args[@]}" -- steam "${steam_args[@]}" &
gamescope_pid=$!

# Rest mode after a while without controller input (never mid-game).
if ((${ALLOY_AUTO_REST_MINUTES:-0} > 0)); then
  alloy-ps-button --target none --idle-minutes "$ALLOY_AUTO_REST_MINUTES" &
  watcher_pid=$!
fi

# Steam's "Switch to Desktop" runs steamos-session-select inside Steam's
# sandbox, which can only leave a note in $state. Act on it from out here.
while kill -0 "$gamescope_pid" 2>/dev/null; do
  if [[ -e "$state/end-request" ]]; then
    rm -f "$state/end-request"
    quit_steam "$gamescope_pid"
  fi
  sleep 1
done

wait "$gamescope_pid" || true

if [[ -e "$state/steam-shutdown" ]]; then
  rm -f "$state/steam-shutdown"
  systemctl poweroff
elif [[ -e "$state/steam-reboot" ]]; then
  rm -f "$state/steam-reboot"
  systemctl reboot
fi
