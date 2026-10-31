# Emulation: RetroDECK from Flathub, which Tender (the RomM plugin, see
# decky.nix) launches games through. It brings its own emulators and ES-DE,
# which nixpkgs no longer packages.
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
  options.alloy.modes.game.retrodeck =
    lib.mkEnableOption "RetroDECK (emulators and ES-DE) from Flathub"
    // {
      default = true;
    };

  config = lib.mkIf (cfg.enable && cfg.game.retrodeck) {
    assertions = [
      {
        assertion = config.alloy.vanilla.flatpak or false;
        message = "alloy.modes.game.retrodeck needs Flatpak: set alloy.vanilla.flatpak = true.";
      }
    ];

    # Installed once, in the background: it's a big download and boot
    # shouldn't wait for it. After that, Flatpak updates it like any app.
    # It keeps retrying instead of failing: the network can be down for a
    # moment, e.g. while nixos-rebuild switch restarts NetworkManager, and a
    # failed unit would fail the whole switch.
    systemd.services.alloy-retrodeck = {
      description = "Install RetroDECK from Flathub";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "alloy-flathub.service"
      ];
      path = [ pkgs.flatpak ];
      serviceConfig.Type = "exec";
      # Don't restart an install that's under way on every switch.
      restartIfChanged = false;
      script = ''
        until flatpak info --system net.retrodeck.retrodeck >/dev/null 2>&1; do
          flatpak install --system --noninteractive flathub net.retrodeck.retrodeck && break
          echo "alloy: couldn't install RetroDECK (offline?), trying again in a minute" >&2
          sleep 60
        done
      '';
    };
  };
}
