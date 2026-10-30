# Desktop mode: Hyprland, plus the three ways into game mode (and the
# launcher for rest mode).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.modes;
  inherit (cfg.packages) ps-button;

  game-mode-launcher = pkgs.makeDesktopItem {
    name = "alloy-game-mode";
    desktopName = "Game Mode";
    comment = "Switch to Steam Big Picture";
    exec = "alloy-mode game";
    icon = "steam";
    categories = [ "Game" ];
  };

  rest-mode-launcher = pkgs.makeDesktopItem {
    name = "alloy-rest-mode";
    desktopName = "Rest Mode";
    comment = "Screen off, downloads keep going; press PS to wake";
    exec = "alloy-mode rest";
    icon = "system-suspend";
    categories = [ "System" ];
  };
in
{
  config = lib.mkIf cfg.enable {
    programs.hyprland.enable = true;

    environment.systemPackages = [
      game-mode-launcher
    ]
    ++ lib.optional cfg.rest.enable rest-mode-launcher
    ++ lib.optional cfg.psButton.enable ps-button;

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
