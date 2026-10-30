# Your home-manager config. With the Omarchy frontend on, Omarchy itself owns
# your desktop dotfiles (~/.config/hypr, the bar, themes); put personal tools
# and settings that aren't Omarchy's here.
{ ... }:
{
  imports = [
    ./plain-desktop.nix
    ./sync.nix
  ];

  home.stateVersion = "26.11";
}
