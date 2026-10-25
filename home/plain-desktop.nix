# The plain Hyprland desktop, used only when the Omarchy frontend is off
# (alloy.omarchy.enable = false): a bar, a launcher, a terminal, basic keybinds.
{
  lib,
  pkgs,
  osConfig,
  ...
}:
lib.mkIf (!(osConfig.alloy.omarchy.enable or false)) {
  home.packages = with pkgs; [
    nautilus
    pavucontrol
    wl-clipboard
    grim
    slurp
  ];

  programs.foot.enable = true;
  programs.fuzzel.enable = true;
  programs.waybar = {
    enable = true;
    systemd.enable = true;
  };
  services.mako.enable = true;

  wayland.windowManager.hyprland.settings = {
    "$mod" = "SUPER";
    "$terminal" = "foot";
    "$launcher" = "fuzzel";
    "$browser" = "firefox";

    monitor = [ ",preferred,auto,1" ];

    general = {
      gaps_in = 4;
      gaps_out = 8;
      border_size = 2;
      layout = "dwindle";
    };

    misc = {
      disable_hyprland_logo = true;
      disable_splash_rendering = true;
    };

    bind = [
      "$mod, Return, exec, $terminal"
      "$mod, Space, exec, $launcher"
      "$mod, B, exec, $browser"
      "$mod, E, exec, nautilus"
      "$mod, W, killactive"
      "$mod, F, fullscreen"
      "$mod, T, togglefloating"
      "$mod, left, movefocus, l"
      "$mod, right, movefocus, r"
      "$mod, up, movefocus, u"
      "$mod, down, movefocus, d"
      ", Print, exec, grim -g \"$(slurp)\" - | wl-copy"
      # Leave both modes for the TTY (run alloy-session to come back).
      "$mod SHIFT, Escape, exec, alloy-mode shell"
    ]
    ++ builtins.concatLists (
      builtins.genList (
        i:
        let
          ws = toString (i + 1);
        in
        [
          "$mod, ${ws}, workspace, ${ws}"
          "$mod SHIFT, ${ws}, movetoworkspace, ${ws}"
        ]
      ) 9
    );

    bindm = [
      "$mod, mouse:272, movewindow"
      "$mod, mouse:273, resizewindow"
    ];
  };
}
