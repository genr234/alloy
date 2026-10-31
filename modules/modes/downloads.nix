# Downloads that keep going in rest mode: aria2 as a user service, so the
# desktop closing (for rest or game mode) doesn't stop them, plus
# alloy-download to queue links and extract finished archive sets, and the
# AriaNg page to watch them. Rest mode waits for them before shutting down.
#
#   browser (Aria2 Explorer) --.
#   alloy-download URL...    --+--> aria2 (alloy-downloads.service) --> ~/Downloads
#   AriaNg (Downloads app)   --'        |
#                                       '-- on complete: extract name.part*.rar
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption mkEnableOption types;
  cfg = config.alloy.modes.downloads;

  # 7-Zip with its RAR decoder (unfree unRAR licence): one tool for .rar,
  # .7z and .zip sets.
  sevenZip = pkgs._7zz-rar;

  env = {
    ALLOY_DOWNLOADS_DIR = cfg.directory;
    ALLOY_DOWNLOADS_DELETE_ARCHIVES = if cfg.deleteArchives then "1" else "0";
    ALLOY_7Z = lib.getExe sevenZip;
    ALLOY_ARIANG = "${pkgs.ariang}/share/ariang/index.html";
  };

  download-cli = pkgs.writers.writePython3Bin "alloy-download" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./scripts/alloy-download.py);

  alloy-download = pkgs.symlinkJoin {
    name = "alloy-download";
    paths = [ download-cli ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/alloy-download \
        ${
          lib.concatStrings (lib.mapAttrsToList (k: v: "--set-default ${k} ${lib.escapeShellArg v} ") env)
        } \
        --prefix PATH : ${lib.makeBinPath [ pkgs.xdg-utils ]}
      # aria2 calls its hook with exactly three arguments.
      cat > $out/bin/alloy-download-hook <<EOF
      #!${pkgs.runtimeShell}
      exec $out/bin/alloy-download hook "\$@"
      EOF
      chmod +x $out/bin/alloy-download-hook
    '';
  };

  aria2-service = pkgs.writeShellApplication {
    name = "alloy-aria2";
    runtimeInputs = [
      pkgs.aria2
      pkgs.coreutils
      alloy-download
    ];
    text = builtins.readFile ./scripts/alloy-aria2.sh;
  };

  downloads-launcher = pkgs.makeDesktopItem {
    name = "alloy-downloads";
    desktopName = "Downloads";
    comment = "Downloads that keep going in rest mode (aria2)";
    exec = "alloy-download web";
    icon = "ariang";
    categories = [ "Network" ];
  };
in
{
  options.alloy.modes.downloads = {
    enable = mkEnableOption "background downloads (aria2) that rest mode waits for" // {
      default = true;
    };

    package = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
      default = alloy-download;
      description = "alloy-download, for the rest session.";
    };

    directory = mkOption {
      type = types.str;
      default = "Downloads";
      description = "Where downloads go: a path relative to the home directory, or absolute.";
    };

    concurrent = mkOption {
      type = types.ints.positive;
      default = 3;
      description = "Files downloaded at the same time; the rest wait in the queue.";
    };

    connections = mkOption {
      type = types.ints.positive;
      default = 4;
      description = "Connections per file (each file is split, like IDM does).";
    };

    deleteArchives = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Delete the archive parts once a set has been extracted. Off by
        default: until you've checked the extracted files, the parts are
        your only copy.
      '';
    };
  };

  config = lib.mkIf (config.alloy.modes.enable && cfg.enable) {
    environment.systemPackages = [
      alloy-download
      sevenZip
      pkgs.ariang
      downloads-launcher
    ];

    systemd.user.services.alloy-downloads = {
      description = "Alloy background downloads (aria2)";
      wantedBy = [ "default.target" ];
      unitConfig.ConditionUser = config.alloy.modes.user;
      environment = {
        inherit (env) ALLOY_DOWNLOADS_DIR;
        ALLOY_DOWNLOADS_CONCURRENT = toString cfg.concurrent;
        ALLOY_DOWNLOADS_CONNECTIONS = toString cfg.connections;
      };
      serviceConfig = {
        ExecStart = lib.getExe aria2-service;
        Restart = "on-failure";
        RestartSec = 10;
        # Out of the way of games: downloads and extraction get the CPU and
        # disk only when nothing else wants them.
        Nice = 10;
        IOSchedulingClass = "idle";
        # aria2 saves its session on the way out.
        TimeoutStopSec = 30;
      };
    };
  };
}
