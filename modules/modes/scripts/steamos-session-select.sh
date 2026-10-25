# Steam's Power menu runs `steamos-session-select <session>`; map it onto
# alloy-mode. Anything that isn't gamescope means "the desktop".

case "${1:-}" in
  gamescope | game) exec alloy-mode game ;;
  *) exec alloy-mode desktop ;;
esac
