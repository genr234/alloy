# Your PS5. Personal choices go here; the PS5 plumbing is in modules/.
{ pkgs, ... }:
let
  user = "ps5"; # change me (and the password below)
in
{
  networking.hostName = "ps5";
  # Time zone: Omarchy sets it automatically. To pin one instead:
  # time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_US.UTF-8";

  nixpkgs.config.allowUnfree = true; # Steam, plus a few Omarchy apps (Obsidian, Spotify)

  # Desktop mode runs Omarchy's own frontend (modules/omarchy).
  alloy.omarchy = {
    enable = true;
    # updateFlake = "github:<you>/<repo>#ps5";  # what Omarchy's Update menu rebuilds from
    # skipPackages = [ "libreoffice-fresh" ];   # leave out Omarchy packages you don't want
  };

  users.users.${user} = {
    isNormalUser = true;
    description = "PS5";
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "render"
    ];
    initialPassword = "ps5"; # change it with `passwd` after the first boot
    # Your PC's SSH public key, for nixos-rebuild --target-host (SSH takes keys only).
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... you@your-pc"
    ];
  };

  alloy.ps5 = {
    label = "alloy";
    # videoMode = null;   # try this if your monitor stays black
    # wifi.enable = true; # built-in Wi-Fi on consoles with the IW620 chip (default)
    # tuning.zen2 = true; # CachyOS-style -march=znver2 kernel and Mesa (measure first)
  };

  # The Cachix cache CI pushes to (see .github/workflows/ci.yml).
  # alloy.cache = {
  #   name = "alloy";
  #   publicKey = "alloy.cachix.org-1:...";
  # };

  alloy.modes = {
    inherit user;
    default = "desktop";
    game.boost = true;
    # game.scheduler = "scx_lavd";        # CachyOS-style scheduler, once the basics work
    # game.radvNoHiz = true;              # if games show graphical glitches
    # game.performanceOverlay = true;     # Steam's overlay via MangoHud (default)
    # game.protonGE = true;               # GE-Proton in Steam (default)
  };

  # The VanillaOS layer (defaults shown).
  # alloy.vanilla = {
  #   generationPicker = true;  # press Enter at boot to start an older system
  #   autoFallback = true;      # a system that never reaches the desktop is rolled back
  #   containers = true;        # distrobox (other distros' apps)
  #   flatpak = true;           # Flatpak + Flathub
  # };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${user} = import ../../home;
  };

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
  ];

  # SSH, for nixos-rebuild --target-host from your PC. Keys only, because the
  # initial password above is public in this repo; add your key to the user.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
  };

  system.stateVersion = "26.11";
}
