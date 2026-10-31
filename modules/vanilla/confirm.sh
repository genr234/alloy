# alloy-boot-confirm: decide whether this boot worked.
#
# The generation picker (stage 1) leaves the generation it booted in
# /var/lib/alloy/boot-trial. Once desktop, game or rest mode has started and stayed
# up for 20 seconds, this removes the marker: the generation is good. If the
# marker is still there at the next boot, the picker falls back to the
# previous generation.
#
# After such a fallback (alloy.fallback=1 on the kernel command line), a
# confirmed boot also makes this generation the default again, like
# `nixos-rebuild switch --rollback`, so the broken one isn't retried.

marker=/var/lib/alloy/boot-trial
[[ -f $marker ]] || exit 0

session_log=$(journalctl --no-pager -b -o short-unix -t alloy-session 2>/dev/null || true)
last=$(grep -E 'starting (desktop|game|rest) mode|mode ended after|keep exiting' <<<"$session_log" | tail -n 1 || true)

if [[ $last != *"starting "*" mode"* ]]; then
  exit 0 # no session running (yet)
fi
started=${last%%.*}
now=$(date +%s)
if ((now - started < 20)); then
  exit 0 # give it a little longer
fi

rm -f "$marker"
logger -t alloy-boot-confirm -- "boot confirmed: $(readlink -f /run/current-system)"

if grep -qw alloy.fallback=1 /proc/cmdline; then
  logger -t alloy-boot-confirm -- "this boot was a fallback; making it the default again"
  nix-env -p /nix/var/nix/profiles/system --set "$(readlink -f /run/current-system)"
  /run/current-system/bin/switch-to-configuration boot
fi

systemctl --no-block stop alloy-boot-confirm.timer
