# Decky Loader: plugins in Steam's Quick Access menu (the "..." button).
#
#   Alloy           rest mode, its switches and boost; ours, installed here
#   Tender          your RomM library inside Steam, launched through RetroDECK
#   Decky Framegen  OptiScaler per game: FSR 4 (RDNA2 build), FSR 3.1 frame
#                   generation, XeSS
#   lsfg-vk         Lossless Scaling frame generation (needs Lossless Scaling)
#
# Only Alloy is installed by Nix; the others install from Decky's own store or
# from a URL (see README), so they update the way their authors ship them.
# The loader and its NixOS module come from Jovian-NixOS, used for just that.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.alloy.modes;
  decky = config.jovian.decky-loader;
  alloy-plugin = pkgs.callPackage ../../pkgs/decky-alloy { };
in
{
  imports = [ "${inputs.jovian}/modules/decky-loader.nix" ];

  options.alloy.modes.game.decky.enable =
    lib.mkEnableOption "Decky Loader in game mode, with the Alloy panel"
    // {
      default = true;
    };

  config = lib.mkIf (cfg.enable && cfg.game.decky.enable) {
    jovian.decky-loader = {
      enable = true;
      package = pkgs.callPackage "${inputs.jovian}/pkgs/decky-loader/stable.nix" { };
      # Plugins run as you, so they can reach your Steam library, ~/fgmod
      # (Decky Framegen) and RetroDECK's folders (Tender).
      inherit (cfg) user;
      # What plugin backends shell out to: downloads and archives (Framegen,
      # lsfg-vk), Flatpak (Tender's RetroDECK), and Alloy's own commands.
      extraPackages = with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        gawk
        which
        procps
        curl
        wget
        unzip
        p7zip
        gnutar
        gzip
        xz
        flatpak
        systemd
        cfg.packages.alloy-mode
        cfg.packages.alloy-update
      ];
    };

    # Our plugin belongs to the system: put the current build in place on
    # every start, after Jovian's preStart has set up the state directory.
    systemd.services.decky-loader.preStart = lib.mkAfter ''
      mkdir -p "${decky.stateDir}/plugins"
      rm -rf "${decky.stateDir}/plugins/Alloy"
      cp -r --no-preserve=mode ${alloy-plugin} "${decky.stateDir}/plugins/Alloy"
      chown -R "${decky.user}:" "${decky.stateDir}/plugins/Alloy"
    '';

    # The Alloy panel's defaults, from the options in default.nix.
    environment.etc."alloy/modes.json".text = builtins.toJSON {
      rest = cfg.rest.enable;
      inherit (cfg.rest) autoRestMinutes shutdownWhenDone;
      boost = cfg.game.boost;
    };
  };
}
