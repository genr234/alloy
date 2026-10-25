# omarchy-hyprland-titlebars: the Hyprland plugin Omarchy's floating
# workspaces load (default/hypr/workspace-modes.lua). A plugin only loads into
# the exact Hyprland it was built against, so the module overrides `hyprland`
# with programs.hyprland.package.
{
  lib,
  hyprland,
  hyprlandPlugins,
  fetchFromGitHub,
  cmake,
}:

hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
  pluginName = "omarchy-hyprland-titlebars";
  version = "0.2.2";
  inherit hyprland;

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omarchy-hyprland-titlebars";
    tag = "v${finalAttrs.version}";
    hash = "sha256-K7IHVqS0HHkJM/ytq1YF+seWB4tEs80eFJK8TAHbqbQ=";
  };

  nativeBuildInputs = [ cmake ];

  # Installs lib/omarchy-hyprland-titlebars/titlebars.so, the path Omarchy
  # loads (as /usr/lib/..., rewritten to /run/current-system/sw/lib/...).

  meta = {
    description = "Titlebars for Omarchy's floating workspaces";
    homepage = "https://github.com/omacom/omarchy-hyprland-titlebars";
    license = with lib.licenses; [
      bsd3
      mit
    ];
    platforms = lib.platforms.linux;
  };
})
