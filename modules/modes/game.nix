# Game mode: Steam + gamescope, with the PS5 display fixes from ps5-linux-image
# and the CachyOS-style gaming extras (overlay, GameMode, GE-Proton).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.alloy.modes;
in
{
  config = lib.mkIf cfg.enable {
    programs.steam = {
      enable = true;
      # Steam's "Switch to Desktop" runs steamos-session-select from inside its
      # sandbox, so it has to be on Steam's PATH. MangoHud is there so games
      # can use it too (launch option: mangohud %command%).
      extraPackages = [
        cfg.packages.steamos-session-select
        cfg.packages.alloy-mode
      ]
      ++ lib.optional cfg.game.performanceOverlay pkgs.mangohud
      ++ lib.optional cfg.game.gamemode pkgs.gamemode;
      extraCompatPackages = lib.optional cfg.game.protonGE pkgs.proton-ge-bin;
    };

    programs.gamescope.enable = true;
    programs.gamemode.enable = cfg.game.gamemode;
    users.users.${cfg.user}.extraGroups = lib.optional cfg.game.gamemode "gamemode";
    environment.systemPackages = lib.optional cfg.game.performanceOverlay pkgs.mangohud;

    # gamescope would otherwise signal BT.2020 colorimetry, which the PS5's
    # internal DP-to-HDMI bridge turns into a black screen.
    environment.etc."gamescope/scripts/90-ps5-srgb.lua".source = ./ps5-srgb.lua;
  };
}
