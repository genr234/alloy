# The Omarchy frontend: Omarchy's own files (pinned in flake.nix as the
# `omarchy` input) running on NixOS, set up the way its Arch packages and
# installer set it up. See pkgs/omarchy/default.nix for what's changed.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.alloy.omarchy;
  modes = config.alloy.modes;
  src = inputs.omarchy;

  # --- Omarchy's package list (install/omarchy-base.packages) -> nixpkgs
  archPackages = lib.pipe (builtins.readFile "${src}/install/omarchy-base.packages") [
    (lib.splitString "\n")
    (map (l: lib.trim (builtins.head (lib.splitString "#" l))))
    (lib.filter (l: l != ""))
  ];

  # Same software, different name in nixpkgs.
  renames = {
    base-devel = "gcc";
    bluez-utils = "bluez";
    disktree-bin = "disktree";
    hyprland-guiutils = "hyprland-qtutils";
    libreoffice-fresh = "libreoffice";
    libvips = "vips";
    lua51 = "lua5_1";
    mariadb-libs = "libmysqlclient";
    mise-bin = "mise";
    noto-fonts-cjk = "noto-fonts-cjk-sans";
    noto-fonts-emoji = "noto-fonts-color-emoji";
    nvim = "neovim";
    postgresql-libs = "libpq";
    qt6-base = "qt6.qtbase";
    qt6-declarative = "qt6.qtdeclarative";
    qt6-imageformats = "qt6.qtimageformats";
    qt6-multimedia = "qt6.qtmultimedia";
    qt6-svg = "qt6.qtsvg";
    qt6-wayland = "qt6.qtwayland";
    tesseract-data-eng = "tesseract";
    tree-sitter-cli = "tree-sitter";
    ttf-ia-writer = "ia-writer-quattro";
    ttf-jetbrains-mono-nerd-basic = "nerd-fonts.jetbrains-mono";
    woff2-font-awesome = "font-awesome";
    yaru-icon-theme = "yaru-theme";
  };

  # Provided another way below (a NixOS service, the input method, the
  # Python environment, the mpv wrapper), but still "installed" for Omarchy.
  providedOtherwise = [
    "fcitx5"
    "fcitx5-chewing"
    "fcitx5-chinese-addons"
    "fcitx5-gtk"
    "fcitx5-hangul"
    "fcitx5-mozc"
    "fcitx5-qt"
    "fcitx5-table-extra"
    "mpv"
    "mpv-mpris"
    "python-gobject"
    "python-poetry-core"
    "docker"
    "docker-buildx"
    "docker-compose"
    "nss-mdns"
    "gvfs-mtp"
    "gvfs-nfs"
    "gvfs-smb"
  ];

  # Arch plumbing that NixOS does differently or the PS5 doesn't need.
  notNeeded = [
    "asdcontrol" # Apple displays
    "expac"
    "kernel-modules-hook"
    "pacman-contrib"
    "plymouth"
    "qemu-user-static-binfmt"
    "sddm" # alloy logs in on tty1 itself
    "ufw" # networking.firewall
    "ufw-docker"
    "vi" # vim is installed
    "yay"
  ];

  # Omarchy's own apps (its omarchy-pkgs repo), packaged in pkgs/omarchy-apps.
  # The titlebar plugin has to match the Hyprland that runs.
  omarchyApps = (import ../../pkgs/omarchy-apps { inherit pkgs; }).overrideScope (
    _: prev: {
      omarchy-hyprland-titlebars = prev.omarchy-hyprland-titlebars.override {
        hyprland = config.programs.hyprland.package;
      };
    }
  );
  appNames = [
    "aether"
    "gliff"
    "hype"
    "monologue"
    "omacalc"
    "omacut"
    "omarchy-hyprland-titlebars"
    "omarchy-nvim"
    "omasnap"
    "omawrite"
    "owe"
    "owe-lockfeed"
    "signed"
    "tobi-try"
    "ttfx"
  ];

  # Not packaged: proprietary, and a voice dictation app is little use on a PS5.
  notPackaged = [ "superwhisper-bin" ];

  fontNames = [
    "noto-fonts"
    "noto-fonts-cjk"
    "noto-fonts-emoji"
    "ttf-ia-writer"
    "ttf-jetbrains-mono-nerd-basic"
    "woff2-font-awesome"
  ];

  resolve =
    name:
    let
      attr = renames.${name} or name;
      found = builtins.tryEval (lib.attrByPath (lib.splitString "." attr) null pkgs);
    in
    if lib.elem name appNames then
      omarchyApps.${name}
    else if found.success && lib.isDerivation found.value then
      found.value
    else
      null;

  wanted = lib.filter (
    n:
    !(lib.elem n providedOtherwise)
    && !(lib.elem n notNeeded)
    && !(lib.elem n notPackaged)
    && !(lib.elem n cfg.skipPackages)
  ) archPackages;

  resolved = lib.filter (n: resolve n != null) wanted;
  unresolved = lib.filter (n: resolve n == null) wanted;
  fonts = map resolve (lib.filter (n: lib.elem n fontNames) resolved);
  packages = map resolve (lib.filter (n: !(lib.elem n fontNames)) resolved);
  hasApp = n: lib.elem n resolved;

  installedNames =
    resolved
    ++ lib.filter (n: lib.elem n archPackages && !(lib.elem n cfg.skipPackages)) providedOtherwise;

  # --- the game-mode key and PS-button listener, as Omarchy Lua
  extraLua = ''
    -- Added by alloy (modules/omarchy). Loaded at the end of Omarchy's defaults.
    o.bind("${cfg.gameModeKey}", "Game mode", "alloy-mode game")
  ''
  + lib.optionalString modes.psButton.enable ''
    hl.on("hyprland.start", function()
      hl.exec_cmd("alloy-ps-button")
    end)
  '';

  omarchy = pkgs.callPackage ../../pkgs/omarchy {
    inherit src extraLua;
    installedPackages = installedNames;
    gameModeMenuEntry = modes.enable;
  };

  seed = pkgs.writeShellApplication {
    name = "alloy-omarchy-seed";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    # Colon-separated, applied in order: Omarchy's skel, then omarchy-nvim's.
    runtimeEnv.ALLOY_OMARCHY_SKEL = lib.concatStringsSep ":" (
      [ "${omarchy}/share/omarchy-skel" ]
      ++ lib.optional (hasApp "omarchy-nvim") "${omarchyApps.omarchy-nvim}/share/omarchy-nvim/skel"
    );
    text = builtins.readFile ./seed.sh;
  };

  session = pkgs.writeShellApplication {
    name = "alloy-omarchy-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
      seed
      omarchy
      config.programs.uwsm.package
    ];
    text = builtins.readFile ./session.sh;
  };

  # Omarchy's sudoers drop-ins, pointed at NixOS paths. Locale generation is
  # left out: NixOS builds locales declaratively (i18n.supportedLocales).
  sudoers = lib.pipe (builtins.readDir "${src}/etc/sudoers.d") [
    (lib.filterAttrs (n: t: t == "regular" && n != "omarchy-locale-generate"))
    lib.attrNames
    (map (n: builtins.readFile "${src}/etc/sudoers.d/${n}"))
    lib.concatLines
    (builtins.replaceStrings [ "/usr/bin/" ] [ "/run/current-system/sw/bin/" ])
  ];

  copyEtc = path: {
    "${path}".source = "${src}/etc/${path}";
  };
in
{
  options.alloy.omarchy = {
    enable = lib.mkEnableOption "the Omarchy frontend (github.com/basecamp/omarchy) in desktop mode";

    gameModeKey = lib.mkOption {
      type = lib.types.str;
      default = "SUPER + CTRL + G";
      description = "Key for game mode, in Omarchy's notation. (SUPER + G is Omarchy's window grouping.)";
    };

    updateFlake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "github:you/alloy#ps5";
      description = "Flake that Omarchy's Update menu rebuilds from (omarchy-update).";
    };

    skipPackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "libreoffice-fresh"
        "dotnet-runtime"
      ];
      description = "Omarchy packages (Arch names, from install/omarchy-base.packages) to leave out.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = omarchy;
      description = "The Omarchy package built for this system.";
    };

    apps = lib.mkOption {
      type = lib.types.raw;
      readOnly = true;
      default = omarchyApps;
      description = "Omarchy's own apps (pkgs/omarchy-apps), built for this system.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings = lib.optional (unresolved != [ ]) ''
      alloy.omarchy: these Omarchy packages have no nixpkgs match and were left out:
        ${lib.concatStringsSep " " unresolved}
      Map them in modules/omarchy/default.nix (renames) or skip them with alloy.omarchy.skipPackages.
    '';

    alloy.modes.desktop = {
      command = "alloy-omarchy-session";
      manageHyprlandConfig = false;
    };

    environment.systemPackages = [
      omarchy
      seed
      session
      pkgs.gnumake # the rest of base-devel
      # Commands Omarchy uses that Arch pulls in as dependencies of something else.
      pkgs.desktop-file-utils # update-desktop-database
      pkgs.xdg-user-dirs
      pkgs.xdg-utils
      pkgs.libnotify # notify-send
      pkgs.gum
      (pkgs.mpv.override { scripts = [ pkgs.mpvScripts.mpris ]; })
      (pkgs.python3.withPackages (p: [
        p.pygobject3
        p.poetry-core
      ]))
    ]
    ++ packages;

    # Omarchy expects to live in /usr/share/omarchy (several commands check that
    # exact path). Keep a root-owned, ordinary copy there, refreshed whenever
    # the pinned Omarchy changes, like the Arch package would install it.
    system.activationScripts.omarchy = {
      deps = [ "specialfs" ];
      text = ''
        src=${omarchy}/share/omarchy
        dest=/usr/share/omarchy
        if [ "$(cat "$dest/.alloy-source" 2>/dev/null)" != "$src" ]; then
          mkdir -p /usr/share
          rm -rf /usr/share/.omarchy-new /usr/share/.omarchy-old
          cp -r "$src" /usr/share/.omarchy-new
          chmod -R u+w,go-w /usr/share/.omarchy-new
          echo "$src" > /usr/share/.omarchy-new/.alloy-source
          if [ -e "$dest" ]; then mv "$dest" /usr/share/.omarchy-old; fi
          mv /usr/share/.omarchy-new "$dest"
          rm -rf /usr/share/.omarchy-old
        fi
      '';
    };

    # The env bootstrap Omarchy sources from /etc/profile.d (OMARCHY_PATH etc.).
    environment.extraInit = ''
      [ -r /usr/share/omarchy/default/bash/env-bootstrap ] && . /usr/share/omarchy/default/bash/env-bootstrap
    '';
    environment.etc = lib.mkMerge (
      map copyEtc [
        "fastfetch/config.jsonc"
        "mpv/mpv.conf"
        "xdg/kitty/kitty.conf"
        "xkb"
      ]
      ++ [
        {
          "environment.d/10-omarchy-fcitx.conf".source = "${src}/default/environment.d/10-omarchy-fcitx.conf";
          "alloy/flake" = lib.mkIf (cfg.updateFlake != null) { text = cfg.updateFlake; };
        }
      ]
    );
    # share/uwsm/env.d, share/omarchy-nix, share/fzf, ... under /run/current-system/sw,
    # and the titlebar plugin Omarchy loads from /usr/lib/omarchy-hyprland-titlebars.
    environment.pathsToLink = [
      "/share"
      "/lib/omarchy-hyprland-titlebars"
    ];

    # Omarchy's lock screen imports Owe.LockFeed (owe-lockfeed) into Quickshell.
    environment.sessionVariables.QML_IMPORT_PATH = lib.mkIf (hasApp "owe-lockfeed") "${omarchyApps.owe-lockfeed}/${pkgs.qt6.qtbase.qtQmlPrefix}";

    security.sudo.extraConfig = sudoers;

    # Session: Hyprland through uwsm, as Omarchy's session file does.
    programs.hyprland = {
      enable = true;
      withUWSM = true;
    };
    xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

    # User services shipped by omarchy-settings (lib/systemd/user), plus owed.
    systemd.packages = [ omarchy ] ++ lib.optional (hasApp "owe") omarchyApps.owe;

    fonts.packages = fonts ++ [ omarchy ];
    fonts.fontconfig.localConf = builtins.readFile "${src}/default/fontconfig/conf.avail/50-omarchy.conf";

    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5 = {
        waylandFrontend = true;
        addons = with pkgs; [
          fcitx5-gtk
          fcitx5-chewing
          fcitx5-hangul
          fcitx5-mozc
          fcitx5-table-extra
          qt6Packages.fcitx5-chinese-addons
        ];
      };
    };

    # Services Omarchy's packages bring on Arch.
    services.printing.enable = true;
    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };
    services.power-profiles-daemon.enable = true;
    services.gnome.gnome-keyring.enable = true;
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    services.locate = {
      enable = true;
      package = pkgs.plocate;
    };
    virtualisation.docker.enable = true;
    programs.gpu-screen-recorder.enable = true;
    users.users.${modes.user}.extraGroups = [ "docker" ];

    # Omarchy sets the time zone itself (tzupdate + timedatectl).
    time.timeZone = lib.mkDefault null;
  };
}
