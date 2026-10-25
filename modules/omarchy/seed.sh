# alloy-omarchy-seed: copy Omarchy's shipped defaults (its /etc/skel) into $HOME.
#
#   alloy-omarchy-seed           first login: add files that don't exist yet
#   alloy-omarchy-seed --force   omarchy-reinstall-configs: overwrite them
#
# Files come out of the Nix store read-only, so each copy is made writable and
# keeps its executable bit, exactly as a copy from /etc/skel would on Arch.

force=false
if [[ "${1:-}" == --force ]]; then
  force=true
fi

# ALLOY_OMARCHY_SKEL is a colon-separated list of skel directories (Omarchy's,
# then omarchy-nvim's), applied in that order.
copied=0
IFS=: read -r -a skels <<<"$ALLOY_OMARCHY_SKEL"
for skel in "${skels[@]}"; do
  cd "$skel" || exit 1

  while IFS= read -r -d '' dir; do
    mkdir -p "$HOME/${dir#./}"
  done < <(find . -mindepth 1 -type d -print0)

  while IFS= read -r -d '' file; do
    dest="$HOME/${file#./}"
    if [[ -e "$dest" || -L "$dest" ]]; then
      [[ "$force" == true ]] || continue
      rm -f "$dest"
    fi
    if [[ -L "$file" ]]; then
      cp -P "$file" "$dest"
    else
      cp --no-preserve=mode,ownership "$file" "$dest"
      chmod u+rw "$dest"
      if [[ -x "$file" ]]; then
        chmod +x "$dest"
      fi
    fi
    copied=$((copied + 1))
  done < <(find . \( -type f -o -type l \) -print0)
done

echo "alloy-omarchy-seed: copied $copied file(s) into $HOME"
