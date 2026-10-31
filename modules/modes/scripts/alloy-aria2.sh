# Runs aria2 for alloy-downloads.service (a user service, so it keeps going
# when the desktop closes for rest mode or game mode).
#
# The RPC port only listens on localhost and needs a secret, made once and
# kept in Alloy's state directory: `alloy-download secret` prints it for a
# browser extension. Unfinished downloads are saved in aria2.session and
# picked up again after a restart or a reboot.

state="${XDG_STATE_HOME:-$HOME/.local/state}/alloy"
dir=$ALLOY_DOWNLOADS_DIR
[[ "$dir" == /* ]] || dir="$HOME/$dir"
mkdir -p "$state" "$dir"

if [[ ! -s "$state/aria2-secret" ]]; then
  (
    umask 077
    head -c 24 /dev/urandom | base64 | tr '+/' '-_' >"$state/aria2-secret"
  )
fi
touch "$state/aria2.session"

# The secret goes in a config file rather than on the command line, where
# every process could read it.
conf="${XDG_RUNTIME_DIR:-$state}/alloy-aria2.conf"
(
  umask 077
  echo "rpc-secret=$(<"$state/aria2-secret")" >"$conf"
)

exec aria2c \
  --conf-path="$conf" \
  --enable-rpc --rpc-listen-all=false --rpc-listen-port=6800 \
  --rpc-allow-origin-all=true \
  --dir="$dir" \
  --input-file="$state/aria2.session" --save-session="$state/aria2.session" \
  --save-session-interval=30 \
  --continue=true --auto-file-renaming=false --allow-overwrite=false \
  --file-allocation=none --disk-cache=64M \
  --max-concurrent-downloads="$ALLOY_DOWNLOADS_CONCURRENT" \
  --split="$ALLOY_DOWNLOADS_CONNECTIONS" \
  --max-connection-per-server="$ALLOY_DOWNLOADS_CONNECTIONS" \
  --min-split-size=20M \
  --max-tries=10 --retry-wait=30 --connect-timeout=30 --timeout=60 \
  --seed-time=0 \
  --ca-certificate=/etc/ssl/certs/ca-certificates.crt \
  --on-download-complete=alloy-download-hook \
  --summary-interval=0 --console-log-level=notice
