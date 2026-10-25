# alloy-report: the Phase 0 test results, saved where any computer can read them.
#
#   sudo alloy-report          print the report and save it to the boot partition
#   alloy-report --quiet       only save it (what the timer runs)
#
# The report lands on the FAT32 boot partition as alloy-report.txt, so even if
# the screen stays black you can power off, plug the drive into a PC and read
# it. The previous boot's report is kept as alloy-report.prev.txt.

quiet=false
if [[ "${1:-}" == --quiet ]]; then
  quiet=true
fi

dir="${ALLOY_REPORT_DIR:-/boot/efi}"
boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
current="$(readlink -f /run/current-system 2>/dev/null || echo unknown)"
booted="$(readlink -f /run/booted-system 2>/dev/null || echo unknown)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
shopt -s nullglob

problems=0

# One summary line: ok, not tried yet, or a problem.
check() {
  case "$1" in
    ok) printf '[ok] %s\n' "$2" ;;
    todo) printf '[..] %s\n' "$2" ;;
    *)
      printf '[!!] %s\n' "$2"
      problems=$((problems + 1))
      ;;
  esac
}

# Journal lines, never failing. Usage: j <journalctl args...>
j() {
  timeout 20 journalctl --no-pager -o short-iso "$@" 2>/dev/null || true
}

# The last <n> lines of a command's output, never failing.
last() {
  local n="$1"
  shift
  timeout 20 "$@" 2>&1 | tail -n "$n" || true
}

section() {
  printf '\n== %s\n' "$1"
}

session_log="$(j -b -t alloy-session)"

summary() {
  # Kernel
  local running
  running="$(uname -r)"
  if [[ "$running" == "$ALLOY_KERNEL_VERSION" ]]; then
    check ok "kernel $running with the PS5 patch set"
  else
    check fail "running kernel $running, expected $ALLOY_KERNEL_VERSION"
  fi

  # Boot partition
  if [[ ! -f "$dir/cmdline.txt" ]]; then
    check fail "no cmdline.txt in $dir"
  elif grep -q "init=$booted/init" "$dir/cmdline.txt"; then
    check ok "boot partition holds the generation that is running"
  elif grep -q "init=$current/init" "$dir/cmdline.txt"; then
    check ok "boot partition holds a newer generation, used from the next boot"
  else
    check warn "boot partition holds a different generation (booted from *.old?)"
  fi

  # GPU and display
  if grep -q '^amdgpu ' /proc/modules; then
    check ok "amdgpu driver loaded"
  else
    check fail "amdgpu driver is not loaded"
  fi
  local s connected=""
  for s in /sys/class/drm/card*-*/status; do
    if [[ "$(<"$s")" == connected ]]; then
      local c mode
      c="$(basename "$(dirname "$s")")"
      mode="$(head -n 1 "$(dirname "$s")/modes" 2>/dev/null || true)"
      connected+="${connected:+, }${c#card*-} ${mode:-no mode}"
    fi
  done
  if [[ -n "$connected" ]]; then
    check ok "display connected: $connected"
  else
    check fail "no display reported as connected"
  fi

  # Desktop mode
  local desktop_runs short_runs
  desktop_runs="$(grep -c 'starting desktop mode' <<<"$session_log" || true)"
  short_runs="$(grep -cE 'mode ended after ([0-9]|1[0-4])s' <<<"$session_log" || true)"
  if ((desktop_runs == 0)); then
    check fail "desktop mode never started (autologin or session loop problem)"
  elif grep -q 'keep exiting' <<<"$session_log"; then
    check fail "sessions kept exiting right away; the loop gave up (see Sessions below)"
  elif pgrep -x Hyprland >/dev/null 2>&1; then
    check ok "desktop mode started $desktop_runs time(s); Hyprland is running now"
  else
    check ok "desktop mode started $desktop_runs time(s)"
  fi
  if ((short_runs > 0)); then
    check warn "$short_runs session(s) ended within 15 seconds of starting"
  fi

  # Game mode and the way back
  local game_runs game_ends
  game_runs="$(grep -c 'starting game mode' <<<"$session_log" || true)"
  game_ends="$(grep -c 'game mode ended' <<<"$session_log" || true)"
  if ((game_runs == 0)); then
    check todo "game mode not tried yet this boot (SUPER+CTRL+G)"
  else
    check ok "game mode entered $game_runs time(s)"
    local after_game
    after_game="$(grep -A1 'game mode ended' <<<"$session_log" || true)"
    if ((game_ends > 0)) && [[ "$after_game" == *"starting desktop mode"* ]]; then
      check ok "returned from game mode to the desktop $game_ends time(s) (check the screen was not black)"
    elif ((game_ends == 0)); then
      check todo "still in game mode, or never left it"
    fi
  fi

  # Boost and fan
  if systemctl cat alloy-game-performance.service >/dev/null 2>&1; then
    local on off
    on="$(j -b -u alloy-game-performance | grep -c "boost to 'on'" || true)"
    off="$(j -b -u alloy-game-performance | grep -c "boost to 'off'" || true)"
    if ((on > 0)); then
      check ok "boost switched on $on time(s), off $off time(s)"
    elif ((game_runs > 0)); then
      check fail "game mode ran but boost never switched on (see Performance below)"
    else
      check todo "boost not tried yet (switches on in game mode)"
    fi
  else
    check todo "game-mode boost is turned off in the config"
  fi
  if [[ "$(systemctl is-active ps5-fan.service 2>/dev/null || true)" == active ]]; then
    check ok "fan control is on"
  else
    check fail "fan control is NOT on: avoid long sessions until fixed"
  fi

  # Controllers
  local pads
  pads="$(j -b -t alloy-ps-button | grep -o 'watching .*' | sort -u | sed 's/^watching //' | paste -sd ';' - || true)"
  if [[ -n "$pads" ]]; then
    check ok "controllers seen: $pads"
    if [[ "$(j -b -t alloy-ps-button)" == *"PS button held"* ]]; then
      check ok "PS-button hold switched to game mode"
    else
      check todo "PS-button hold not tried yet"
    fi
  else
    check todo "no controller seen by the PS-button listener yet"
  fi

  # Network and rollback
  if [[ "$(timeout 10 nmcli -t -f STATE general 2>/dev/null || true)" == connected* ]]; then
    check ok "network connected"
  else
    check warn "no network connection"
  fi
  if [[ -f "$dir/bzImage.old" ]]; then
    check ok "previous generation kept as *.old for rollback"
  else
    check todo "no *.old boot files yet (first generation)"
  fi
}

{
  echo "alloy report"
  echo "written: $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "boot: $boot_id"
  echo "system: $current"
  echo
  summary
  echo
  if ((problems == 0)); then
    echo "No problems found."
  else
    echo "$problems problem(s) found; details below."
  fi

  section "System"
  echo "uptime: $(uptime 2>/dev/null || true)"
  echo "kernel: $(uname -a)"
  echo "cmdline: $(cat /proc/cmdline)"
  echo "booted system: $booted"
  echo "generations:"
  last 10 ls -1 /nix/var/nix/profiles

  section "Display"
  for s in /sys/class/drm/card*-*/status; do
    d="$(dirname "$s")"
    echo "$(basename "$d"): $(<"$s"), modes: $(head -n 5 "$d/modes" 2>/dev/null | paste -sd ' ' - || true)"
  done
  last 40 bash -c "journalctl --no-pager -k -b -o short-iso 2>/dev/null | grep -iE 'amdgpu|drm|hdmi|ps5' "

  section "Sessions (this boot)"
  tail -n 40 <<<"$session_log"
  echo "-- desktop warnings and errors"
  last 30 bash -c "journalctl --no-pager -b -o short-iso -t alloy-desktop 2>/dev/null | grep -iE 'warn|err|fail|fatal|crash' "
  echo "-- game mode (last lines)"
  last 40 journalctl --no-pager -b -o short-iso -t alloy-game

  section "Performance"
  last 20 journalctl --no-pager -b -o short-iso -u alloy-game-performance -u scx -u ps5-fan

  section "Controllers"
  last 20 journalctl --no-pager -b -o short-iso -t alloy-ps-button
  grep -E '^N: Name=' /proc/bus/input/devices 2>/dev/null | sed 's/^N: Name=/  /' || true

  section "Network"
  last 20 ip -br addr
  last 20 nmcli device

  section "Failed units"
  last 20 systemctl --failed --no-pager --plain

  section "Errors this boot"
  last 60 journalctl --no-pager -b -p err -o short-iso

  section "Previous boot: sessions and errors"
  last 20 journalctl --no-pager -b -1 -o short-iso -t alloy-session
  last 30 journalctl --no-pager -b -1 -p err -o short-iso
} >"$tmp" 2>&1

if [[ "$quiet" == false ]]; then
  cat "$tmp"
fi

# Save to the boot partition, keeping the previous boot's report.
if [[ -z "${ALLOY_REPORT_DIR:-}" ]] && ! mountpoint -q "$dir"; then
  echo "alloy-report: $dir is not mounted, report not saved" >&2
  exit 0
fi
if [[ ! -w "$dir" ]]; then
  [[ "$quiet" == true ]] || echo "alloy-report: run with sudo to save it to $dir" >&2
  exit 0
fi
if [[ -f "$dir/alloy-report.txt" ]] && ! grep -qx "boot: $boot_id" "$dir/alloy-report.txt"; then
  mv -f "$dir/alloy-report.txt" "$dir/alloy-report.prev.txt"
fi
cp "$tmp" "$dir/alloy-report.txt.new"
mv -f "$dir/alloy-report.txt.new" "$dir/alloy-report.txt"
sync
[[ "$quiet" == true ]] || echo "alloy-report: saved to $dir/alloy-report.txt" >&2
