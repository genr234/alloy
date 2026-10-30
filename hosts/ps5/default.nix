# Your PS5. Personal choices go here; the PS5 plumbing is in modules/.
{ pkgs, ... }:
let
  user = "genr234";
in
{
  networking.hostName = "ps5";
  # Time zone: Omarchy sets it automatically. To pin one instead:
  # time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_US.UTF-8";
  # Text console. The desktop layout is the user's own Hyprland setting.
  console.keyMap = "it";

  nixpkgs.config.allowUnfree = true; # Steam, plus a few Omarchy apps (Obsidian, Spotify)

  # Desktop mode runs Omarchy's own frontend (modules/omarchy).
  alloy.omarchy = {
    enable = true;
    updateFlake = "github:genr234/alloy#ps5"; # what Omarchy's Update menu rebuilds from
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
    initialPassword = "playstationfive"; # change it with `passwd` after the first boot
    # Your PC's SSH public key, for nixos-rebuild --target-host (SSH takes keys only).
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGWhl/Kj5YxVdHCThi5YmYndG2rZ/kWU76iKqOw8AimU riccardocavallaro2020@outlook.it"
    ];
  };

  alloy.ps5 = {
    label = "alloy";
    # videoMode = null;   # try this if your monitor stays black
    # wifi.enable = true; # built-in Wi-Fi on consoles with the IW620 chip (default)
    # tuning.zen2 = true; # CachyOS-style -march=znver2 kernel and Mesa (measure first)
  };

  # The Cachix cache CI pushes to (see .github/workflows/ci.yml).
  alloy.cache = {
    name = "alloy";
    publicKey = "alloy.cachix.org-1:/daEZJTQBuT6WYzOH6Bm5gqe/Y7TIw1giQ+gSEiiBGk=";
  };

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

  # Reach the PS5 from your Mac anywhere, not just at home (`sudo tailscale up`
  # once to log in). Syncthing uses it too when both are on your tailnet.
  services.tailscale.enable = true;
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    # Syncthing on the local network: sync (22000) and discovery (21027).
    allowedTCPPorts = [ 22000 ];
    allowedUDPPorts = [
      22000
      21027
    ];
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
