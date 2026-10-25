# alloy-picker: the generation picker, run as a service in the initrd once the
# root filesystem is mounted at /sysroot. The PS5 loader always boots the
# newest generation, so this is the only place to choose another one: it
# starts the chosen generation's kernel with kexec.
#
#   - Press Enter within 3 seconds to pick an older generation.
#   - If the last boot of this generation never reached a working session
#     (alloy-boot-confirm didn't confirm it), the previous generation starts
#     automatically and, once it works, becomes the default again.
#   - Kernel parameters: alloy.picker=off skips all of this;
#     alloy.generation=previous|/nix/store/... picks one without asking.
#
# ALLOY_TRIAL=1 (set by modules/vanilla) when alloy-boot-confirm runs.

root=/sysroot
tty=/dev/console
cmdline=" $(</proc/cmdline) "
case "$cmdline" in
  *" alloy.picked=1 "* | *" alloy.picker=off "*) exit 0 ;;
esac

say() { echo "alloy: $*" >"$tty"; }

# A path inside the mounted system, following symlinks there: a system's
# kernel and initrd are absolute links into /nix/store, which in the initrd
# only exists under /sysroot.
in_root() {
  local p="$root$1" link
  for _ in 1 2 3 4 5 6 7 8; do
    [[ -L "$p" ]] || break
    link=$(readlink "$p")
    if [[ "$link" == /* ]]; then
      p="$root$link"
    else
      p="$(dirname "$p")/$link"
    fi
  done
  echo "$p"
}

init=""
choice=""
for arg in $cmdline; do
  case "$arg" in
    init=*) init="${arg#init=}" ;;
    alloy.generation=*) choice="${arg#alloy.generation=}" ;;
  esac
done
current="${init%/init}"
profiles="$root/nix/var/nix/profiles"
state="$root/var/lib/alloy"
trial="$state/boot-trial"
[[ -n "$current" && -d "$profiles" ]] || exit 0 # first boot of a fresh image
mkdir -p "$state"

# Generations, newest first: "<number> <system path>".
gens=$(for link in "$profiles"/system-*-link; do
  [[ -L "$link" ]] || continue
  n="${link##*/system-}"
  echo "${n%-link} $(readlink "$link")"
done | sort -rn)
curnum=$(awk -v c="$current" '$2 == c { print $1; exit }' <<<"$gens")
previous=""
if [[ -n "$curnum" ]]; then
  previous=$(awk -v c="$curnum" '$1 < c { print $2; exit }' <<<"$gens")
fi
[[ "$choice" == previous ]] && choice="$previous"

fallback=""
if [[ "${ALLOY_TRIAL:-0}" == 1 && -z "$choice" && -n "$previous" && -f "$trial" &&
  "$(<"$trial")" == "$current" ]]; then
  say "the last boot of this system never reached the desktop."
  say "starting the previous one instead (it becomes the default once it works)."
  choice="$previous"
  fallback=1
  sleep 3
fi

if [[ -z "$choice" && -n "$previous" ]]; then
  say "press Enter within 3 seconds to choose an older system"
  if read -r -t 3 _ <"$tty"; then
    i=0
    while read -r n path; do
      i=$((i + 1))
      when=$(stat -c %y "$profiles/system-$n-link" 2>/dev/null | cut -c1-16)
      mark=""
      [[ "$path" == "$current" ]] && mark="  (newest, default)"
      echo "  $i) generation $n, $when$mark" >"$tty"
    done < <(head -n 9 <<<"$gens")
    printf 'Number [1]: ' >"$tty"
    num=""
    read -r -t 30 num <"$tty" || true
    if [[ "$num" =~ ^[1-9]$ ]]; then
      choice=$(sed -n "${num}p" <<<"$gens" | cut -d' ' -f2)
    fi
  fi
fi

target="${choice:-$current}"
if [[ ! -e "$(in_root "$target/kernel")" ]]; then
  [[ "$target" == "$current" ]] || say "can't find $target/kernel; continuing with the current system"
  target="$current"
fi
if [[ "${ALLOY_TRIAL:-0}" == 1 ]]; then
  echo "$target" >"$trial"
fi
[[ "$target" == "$current" ]] && exit 0

say "starting $target"
params="init=$target/init $(<"$(in_root "$target/kernel-params")") alloy.picked=1"
[[ -n "$fallback" ]] && params="$params alloy.fallback=1"
if kexec -l "$(in_root "$target/kernel")" --initrd="$(in_root "$target/initrd")" --command-line="$params"; then
  sync
  kexec -e
fi
say "couldn't start $target with kexec; continuing with $current"
if [[ "${ALLOY_TRIAL:-0}" == 1 ]]; then
  echo "$current" >"$trial"
fi
exit 0
