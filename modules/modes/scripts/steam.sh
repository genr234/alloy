# Shared by the game and rest sessions, which both run Steam in gamescope.

# Ask Steam to quit (so cloud saves sync), then make sure gamescope is gone.
# Steam gets a minute: a big cloud sync can take a while.
quit_steam() {
  local gamescope_pid=$1
  timeout 20 steam -shutdown >/dev/null 2>&1 || true
  for _ in $(seq 60); do
    kill -0 "$gamescope_pid" 2>/dev/null || return 0
    sleep 1
  done
  kill "$gamescope_pid" 2>/dev/null || true
}

# Decky Loader talks to Steam through its debugging port, which Steam only
# opens when this file exists.
enable_decky() {
  if [[ "${ALLOY_DECKY:-0}" == 1 ]]; then
    mkdir -p "$HOME/.local/share/Steam"
    touch "$HOME/.local/share/Steam/.cef-enable-remote-debugging"
  fi
}
