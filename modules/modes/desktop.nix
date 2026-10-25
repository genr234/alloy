# Desktop mode: Hyprland, plus the three ways into game mode.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.modes;
  inherit (cfg.packages) alloy-mode;

  ps-button-daemon = pkgs.writers.writePython3Bin "alloy-ps-button-daemon" {
    libraries = [ pkgs.python3Packages.evdev ];
  } (builtins.readFile ./scripts/ps-button.py);

  ps-button = pkgs.writeShellApplication {
    name = "alloy-ps-button";
    runtimeInputs = [
      alloy-mode
      pkgs.systemd
    ];
    runtimeEnv.ALLOY_PS_HOLD_SECONDS = toString cfg.psButton.holdSeconds;
    # Log to the journal (journalctl -t alloy-ps-button) so the boot report can
    # show which controllers it saw.
    text = ''exec systemd-cat --identifier=alloy-ps-button ${lib.getExe ps-button-daemon} "$@"'';
  };

  game-mode-launcher = pkgs.makeDesktopItem {
    name = "alloy-game-mode";
    desktopName = "Game Mode";
    comment = "Switch to Steam Big Picture";
    exec = "alloy-mode game";
    icon = "steam";
    categories = [ "Game" ];
  };
in
{
  config = lib.mkIf cfg.enable {
    programs.hyprland.enable = true;

    environment.systemPackages = [ game-mode-launcher ] ++ lib.optional cfg.psButton.enable ps-button;

    # Mode-switching bits of the Hyprland config. Everything else (your
    # keybinds, theme, apps) lives in home/.
    home-manager.users.${cfg.user}.wayland.windowManager.hyprland =
      lib.mkIf cfg.desktop.manageHyprlandConfig
        {
          enable = true;
          package = null; # use the system Hyprland from programs.hyprland
          portalPackage = null;
          settings = {
            bind = [ "${cfg.desktop.gameModeKey}, exec, alloy-mode game" ];
            exec-once = lib.optional cfg.psButton.enable "alloy-ps-button";
          };
        };
  };
}
