# Desktop mode (Hyprland), game mode (Steam Big Picture in gamescope) and
# rest mode (screen off, downloads keep going: the PS5 can't suspend).
#
#   boot -> tty1 autologin -> alloy-session loop
#                               |- desktop (default)  -- game key / "Game Mode" / hold PS -->  game
#                               |- game               -- Steam: Switch to Desktop / quit  -->  desktop
#                               |                     -- Alloy panel / 30 min idle        -->  rest
#                               '- rest               -- press PS / controller on         -->  game
#                                                     -- downloads done                   -->  power off
#
# The loop starts the default mode unless `alloy-mode` asked for another one,
# so every boot, and every way of leaving Steam, ends up on the desktop.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.alloy.modes;
  ps5_control = "${config.alloy.ps5.tools}/bin/ps5_control";
  performance = cfg.game.boost || cfg.game.scheduler != null;

  script =
    name: extra:
    pkgs.writeShellApplication (
      {
        inherit name;
        text = builtins.readFile ./scripts/${name}.sh;
      }
      // extra
    );

  # The game and rest sessions share the Steam helpers in steam.sh.
  steamScript =
    name: extra:
    script name (
      {
        text = builtins.readFile ./scripts/steam.sh + builtins.readFile ./scripts/${name}.sh;
      }
      // extra
    );

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

  alloy-mode = script "alloy-mode" {
    runtimeInputs = [
      pkgs.coreutils
      config.programs.hyprland.package
    ];
  };

  steamos-session-select = script "steamos-session-select" {
    runtimeInputs = [ alloy-mode ];
  };

  sessionEnv = {
    ALLOY_DEFAULT_MODE = cfg.default;
    ALLOY_PERFORMANCE = if performance then "1" else "0";
  };

  # What SteamOS's gamescope-session tells Steam, minus what the PS5 can't do
  # (HDR, VRR and tearing all stop at its DP-to-HDMI bridge). Mostly this
  # unlocks Quick Access menu features: the scaling filter (FSR / NIS /
  # integer, per game), the performance overlay levels and the volume keys.
  steamEnv = {
    STEAM_GAMESCOPE_NIS_SUPPORTED = "1";
    STEAM_GAMESCOPE_FANCY_SCALING_SUPPORT = "1";
    STEAM_MULTIPLE_XWAYLANDS = "1";
    STEAM_ENABLE_VOLUME_HANDLER = "1";
    SRT_URLOPEN_PREFER_STEAM = "1";
    QT_IM_MODULE = "steam";
    GTK_IM_MODULE = "Steam";
    ALLOY_DECKY = if cfg.game.decky.enable then "1" else "0";
  }
  // lib.optionalAttrs cfg.game.performanceOverlay {
    STEAM_USE_MANGOAPP = "1";
    STEAM_MANGOAPP_PRESETS_SUPPORTED = "1";
    STEAM_MANGOAPP_HORIZONTAL_SUPPORTED = "1";
    STEAM_DISABLE_MANGOAPP_ATOM_WORKAROUND = "1";
  };

  desktop-session = script "alloy-desktop-session" {
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      config.programs.hyprland.package
    ];
    runtimeEnv = sessionEnv // {
      ALLOY_DESKTOP_COMMAND = cfg.desktop.command;
    };
  };

  game-session = steamScript "alloy-game-session" {
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      config.programs.gamescope.package
      config.programs.steam.package
      ps-button
    ]
    ++ lib.optional cfg.game.performanceOverlay pkgs.mangohud; # mangoapp
    runtimeEnv =
      sessionEnv
      // steamEnv
      // {
        ALLOY_GAMESCOPE_ARGS = lib.concatStringsSep " " (
          cfg.game.gamescopeArgs
          # A second Xwayland for Steam's overlays, as STEAM_MULTIPLE_XWAYLANDS expects.
          ++ [
            "--xwayland-count"
            "2"
          ]
          ++ lib.optional cfg.game.performanceOverlay "--mangoapp"
        );
        ALLOY_STEAM_ARGS = lib.concatStringsSep " " cfg.game.steamArgs;
        ALLOY_AUTO_REST_MINUTES = toString (if cfg.rest.enable then cfg.rest.autoRestMinutes else 0);
      }
      // lib.optionalAttrs cfg.game.radvNoHiz { RADV_DEBUG = "nohiz"; };
  };

  rest-session = steamScript "alloy-rest-session" {
    runtimeInputs = [
      pkgs.coreutils
      pkgs.systemd
      config.programs.gamescope.package
      config.programs.steam.package
      ps-button
    ];
    runtimeEnv = sessionEnv // {
      ALLOY_DECKY = steamEnv.ALLOY_DECKY;
      ALLOY_STEAM_ARGS = lib.concatStringsSep " " cfg.game.steamArgs;
      ALLOY_REST_SHUTDOWN = if cfg.rest.shutdownWhenDone then "1" else "0";
      ALLOY_REST_QUIET_MINUTES = toString cfg.rest.quietMinutes;
      ALLOY_REST_QUIET_KIBPS = toString cfg.rest.quietKiBps;
    };
  };

  # Powers the display down while resting (the TV sees no signal), through
  # the console framebuffer that takes over once gamescope lets go.
  display-power = pkgs.writeShellApplication {
    name = "alloy-display-power";
    text = ''
      # 4 is FB_BLANK_POWERDOWN, 0 is FB_BLANK_UNBLANK.
      level=$([[ "$1" == off ]] && echo 4 || echo 0)
      for fb in /sys/class/graphics/fb*/blank; do
        [[ -e "$fb" ]] && echo "$level" >"$fb"
      done
    '';
  };

  # Units the session user may start and stop without a password.
  userUnits =
    lib.optional performance "alloy-game-performance.service"
    ++ lib.optional cfg.rest.enable "alloy-display-off.service";

  alloy-session = script "alloy-session" {
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux # logger
      pkgs.systemd
      desktop-session
      game-session
    ]
    ++ lib.optional cfg.rest.enable rest-session;
    runtimeEnv = sessionEnv;
  };
in
{
  imports = [
    ./desktop.nix
    ./game.nix
    ./decky.nix
    ./emulation.nix
  ];

  options.alloy.modes = {
    enable = mkEnableOption "the desktop/game mode session" // {
      default = true;
    };

    user = mkOption {
      type = types.str;
      description = "User that is logged in automatically on tty1 and runs both modes.";
    };

    packages = mkOption {
      type = types.attrsOf types.package;
      internal = true;
      readOnly = true;
      description = "Scripts shared with desktop.nix and game.nix.";
    };

    default = mkOption {
      type = types.enum [
        "desktop"
        "game"
      ];
      default = "desktop";
      description = "Mode started at boot and whenever the other mode exits.";
    };

    desktop.gameModeKey = mkOption {
      type = types.str;
      default = "SUPER, G";
      description = ''
        Hyprland key combination that switches to game mode, for the plain
        Hyprland desktop. With the Omarchy frontend, see alloy.omarchy.gameModeKey.
      '';
    };

    desktop.command = mkOption {
      type = types.str;
      default = "start-hyprland";
      description = "Command that runs the desktop session (must stay in the foreground).";
    };

    desktop.manageHyprlandConfig = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Write the game-mode key and the PS-button listener into a home-manager
        Hyprland config. Turned off by the Omarchy frontend, which owns
        ~/.config/hypr and gets them through default/hypr/alloy.lua instead.
      '';
    };

    psButton = {
      enable = mkEnableOption "switching to game mode by holding a controller's PS button" // {
        default = true;
      };
      holdSeconds = mkOption {
        type = types.numbers.positive;
        default = 1.0;
        description = "How long the PS button must be held.";
      };
    };

    rest = {
      enable = mkEnableOption "rest mode: screen off while Steam and Decky keep downloading" // {
        default = true;
      };

      autoRestMinutes = mkOption {
        type = types.ints.unsigned;
        default = 30;
        description = ''
          Go from game mode to rest mode after this many minutes without
          controller input, but never while a game is running. 0 turns it off;
          the Alloy panel in Steam's Quick Access menu can also turn it off.
        '';
      };

      shutdownWhenDone = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Power off once every download has finished: Steam's download queue
          is empty (as the Alloy panel reports it, when Decky is on) and the
          network has gone quiet. The Alloy panel can override it.
        '';
      };

      quietMinutes = mkOption {
        type = types.ints.positive;
        default = 10;
        description = "How long the network has to stay quiet before shutting down.";
      };

      quietKiBps = mkOption {
        type = types.ints.positive;
        default = 64;
        description = "Download speed (KiB/s) below which the network counts as quiet.";
      };
    };

    game = {
      boost = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Switch on PS5 boost (CPU 3.5 GHz, GPU 2.23 GHz) while in game mode and
          off again on the desktop. The fan stays on in both modes.
        '';
      };

      scheduler = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "scx_lavd";
        description = ''
          sched-ext scheduler to run while in game mode (the kernel has
          CONFIG_SCHED_CLASS_EXT). Off by default until the basics are proven
          on hardware.
        '';
      };

      gamescopeArgs = mkOption {
        type = types.listOf types.str;
        default = [
          "--backend"
          "drm"
          "-e"
          "--prefer-output"
          "DP-1"
          "--sdr-gamut-wideness"
          "0"
        ];
        description = ''
          gamescope flags. The defaults come from ps5-linux-image: drive the
          display directly, target the internal DP connector, and keep SDR in
          sRGB because the PS5's DP-to-HDMI bridge can't handle BT.2020.
        '';
      };

      steamArgs = mkOption {
        type = types.listOf types.str;
        default = [ "-gamepadui" ];
        description = ''
          Steam flags. Not -steamos3: that makes Steam wait for SteamOS
          system updates that never come.
        '';
      };

      # The CachyOS-style gaming layer (phase 3).
      performanceOverlay = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Steam's performance overlay (Quick Access menu > Performance), drawn by
          MangoHud's mangoapp through gamescope, as on a Steam Deck.
        '';
      };

      gamemode = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Feral GameMode. Use it per game with the Steam launch option
          `gamemoderun %command%`.
        '';
      };

      protonGE = mkOption {
        type = types.bool;
        default = true;
        description = "Offer GE-Proton as a compatibility tool in Steam, next to Valve's Proton.";
      };

      radvNoHiz = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Set RADV_DEBUG=nohiz in game mode. ps5-linux recommends it (as on the
          BC-250) when games show graphical glitches.
        '';
      };
    };
  };

  config = lib.mkMerge [
    {
      alloy.modes.packages = {
        inherit
          alloy-mode
          steamos-session-select
          ps-button
          alloy-session
          ;
      };
    }

    (lib.mkIf cfg.enable {
      environment.systemPackages = [
        alloy-session
        alloy-mode
        steamos-session-select
      ];

      # Log in automatically once per boot, then start the session loop on tty1.
      services.getty = {
        autologinUser = cfg.user;
        autologinOnce = true;
      };
      environment.loginShellInit = ''
        if [ "$(tty)" = /dev/tty1 ] && [ "$USER" = ${lib.escapeShellArg cfg.user} ] \
          && [ -z "''${ALLOY_MODE:-}" ] && [ -z "''${WAYLAND_DISPLAY:-}" ]; then
          alloy-session
        fi
      '';

      # Game-mode performance profile, started and stopped by the game session.
      systemd.services.alloy-game-performance = lib.mkIf performance {
        description = "Game mode performance profile";
        wants = lib.optional (cfg.game.scheduler != null) "scx.service";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = if cfg.game.boost then "-${ps5_control} --boost on" else "${pkgs.coreutils}/bin/true";
          ExecStop = if cfg.game.boost then "-${ps5_control} --boost off" else "${pkgs.coreutils}/bin/true";
        };
      };

      services.scx = lib.mkIf (cfg.game.scheduler != null) {
        enable = true;
        scheduler = cfg.game.scheduler;
      };
      systemd.services.scx = lib.mkIf (cfg.game.scheduler != null) {
        wantedBy = lib.mkForce [ ];
        partOf = [ "alloy-game-performance.service" ];
      };

      systemd.services.alloy-display-off = lib.mkIf cfg.rest.enable {
        description = "Rest mode: display off";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${lib.getExe display-power} off";
          ExecStop = "${lib.getExe display-power} on";
        };
      };

      # Let the session user start/stop only those units without a password.
      security.polkit.enable = true;
      security.polkit.extraConfig = lib.mkIf (userUnits != [ ]) ''
        polkit.addRule(function (action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              ${builtins.toJSON userUnits}.indexOf(action.lookup("unit")) >= 0 &&
              subject.user == ${builtins.toJSON cfg.user}) {
            return polkit.Result.YES;
          }
        });
      '';
    })
  ];
}
