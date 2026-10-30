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
      script = ''
        flatpak info --system net.retrodeck.retrodeck >/dev/null 2>&1 ||
          flatpak install --system --noninteractive flathub net.retrodeck.retrodeck
      '';
    };
  };
}
