# Rest mode: the screen goes dark while downloads keep going.
#
# The PS5 can't suspend, so this is the next best thing. Steam runs in a
# gamescope with no display (--backend headless), so its downloads, Decky
# plugins (RomM games via Tender) and everything else carry on while the TV
# sees no signal and boost stays off. Pressing PS, or turning a controller
# back on, wakes the console into game mode.
#
# Once the network has been quiet for ALLOY_REST_QUIET_MINUTES and Steam's
# download queue is empty (every download done), the console shuts down,
# unless that was switched off in the Alloy panel. The queue comes from the
# Alloy panel (steam-downloads); without Decky, the network alone decides.

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
mkdir -p "$state"
rm -f "$state/end-request" "$state/steam-downloads"

export ALLOY_MODE=rest
export LIBSEAT_BACKEND=logind
export WLR_LIBINPUT_NO_DEVICES=1

read -r -a steam_args <<<"$ALLOY_STEAM_ARGS"

watcher_pid=
finish() {
  [[ -z "$watcher_pid" ]] || kill "$watcher_pid" 2>/dev/null || true
  rm -f "$state/rest-active" "$state/end-request" "$state/steam-downloads"
  systemctl stop alloy-display-off.service 2>/dev/null || true
}
trap finish EXIT

systemctl start alloy-display-off.service ||
  echo "alloy: could not switch the display off" >&2
enable_decky
touch "$state/rest-active"

gamescope --backend headless -- steam "${steam_args[@]}" &
gamescope_pid=$!
alloy-ps-button --hold 0 --wake-on-connect &
watcher_pid=$!

# Bytes received on the real network devices. Loopback, bridges and veths
# (podman, distrobox) have no device link: their traffic is either local or
# already counted on the real interface.
rx_bytes() {
  local total=0 iface
  for iface in "${ALLOY_NET_DIR:-/sys/class/net}"/*; do
    [[ -e "$iface/device" ]] || continue
    total=$((total + $(<"$iface/statistics/rx_bytes")))
  done
  echo "$total"
}

shutdown_when_done() {
  local setting=$ALLOY_REST_SHUTDOWN
  if [[ -f "$state/shutdown-when-done" ]]; then
    [[ "$(<"$state/shutdown-when-done")" == off ]] && setting=0 || setting=1
  fi
  [[ "$setting" == 1 ]]
}

# Steam has nothing left to download, or the Alloy panel hasn't said.
steam_queue_empty() {
  local pending=0
  [[ -f "$state/steam-downloads" ]] && pending=$(<"$state/steam-downloads")
  [[ "$pending" == 0 ]]
}

sample=${ALLOY_REST_SAMPLE_SECONDS:-60}
busy_bytes=$((ALLOY_REST_QUIET_KIBPS * 1024 * sample))
quiet=0 ticks=0 poweroff=0
last_rx=$(rx_bytes)

while kill -0 "$gamescope_pid" 2>/dev/null; do
  if [[ -e "$state/end-request" ]]; then
    rm -f "$state/end-request"
    quit_steam "$gamescope_pid"
    break
  fi
  sleep 1
  ticks=$((ticks + 1))
  ((ticks >= sample)) || continue

  ticks=0
  rx=$(rx_bytes)
  if ((rx - last_rx < busy_bytes)); then
    quiet=$((quiet + 1))
  else
    quiet=0
  fi
  last_rx=$rx
  if ((quiet >= ALLOY_REST_QUIET_MINUTES)) && shutdown_when_done && steam_queue_empty; then
    echo "alloy: downloads look finished (network quiet), shutting down"
    poweroff=1
    quit_steam "$gamescope_pid"
    break
  fi
done

wait "$gamescope_pid" || true
if ((poweroff)); then
  systemctl poweroff
fi
