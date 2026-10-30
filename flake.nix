{
  description = "Alloy: a personal NixOS for the PS5 (desktop mode by default, Steam game mode on demand)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # PS5 kernel patch set + .config + built-in VCN firmware.
    # `nix flake update ps5-patches` moves to their latest commit; if the kernel
    # version in their .config changes, the build tells you to bump `linux` below.
    ps5-patches = {
      url = "github:ps5-linux/ps5-linux-patches";
      flake = false;
    };

    # Must match the "# Linux/x86 X.Y.Z" line in ps5-patches/.config.
    linux = {
      url = "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.3.tar.xz";
      flake = false;
    };

    # Omarchy's own files: the desktop frontend (modules/omarchy). Pinned like
    # everything else; `nix flake update omarchy` moves to upstream's latest.
    omarchy = {
      url = "github:basecamp/omarchy";
      flake = false;
    };

    # Built-in Wi-Fi (IW620): NXP's driver at the tag ps5-linux-mwifiex's
    # install.sh names (REF=), plus its patch stack. Keep the two in step.
    mwifiex-nxp = {
      url = "github:nxp-imx/mwifiex/lf-6.18.2_1.0.0";
      flake = false;
    };
    ps5-mwifiex = {
      url = "github:ps5-linux/ps5-linux-mwifiex";
      flake = false;
    };

    # Decky Loader and its NixOS module (modules/modes/decky.nix); nothing
    # else from Jovian is used.
    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      flake = false;
    };

    # ps5_control (fan + boost).
    ps5-tools = {
      url = "github:ps5-linux/ps5-linux-tools";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      ps5 = self.nixosConfigurations.ps5;
    in
    {
      nixosModules = {
        ps5 = ./modules/ps5; # kernel, boot hook, disk image, PS5 hardware
        modes = ./modules/modes; # desktop/game session switching
        omarchy = ./modules/omarchy; # Omarchy's own frontend
        vanilla = ./modules/vanilla; # generation picker, fallback, containers, Flatpak
        cache = ./modules/cache.nix; # trust the CI binary cache
      };

      nixosConfigurations.ps5 = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs; };
        modules = [
          home-manager.nixosModules.home-manager
          self.nixosModules.ps5
          self.nixosModules.modes
          self.nixosModules.omarchy
          self.nixosModules.vanilla
          self.nixosModules.cache
          ./hosts/ps5
        ];
      };

      # The same system with its root on the internal M.2 SSD (see
      # modules/ps5/m2.nix): install with `sudo alloy-m2-install <flake>#ps5-m2`.
      nixosConfigurations.ps5-m2 = ps5.extendModules {
        modules = [ { alloy.ps5.root = "m2"; } ];
      };

      packages.${system} = {
        # nix build            -> result/alloy.img, ready to flash
        default = ps5.config.system.build.ps5Image;
        image = ps5.config.system.build.ps5Image;
        kernel = ps5.config.boot.kernelPackages.kernel;
        wifi-driver = builtins.head ps5.config.boot.extraModulePackages;
        ps5-tools = pkgs.callPackage ./pkgs/ps5-tools.nix { src = inputs.ps5-tools; };
      }
      # Omarchy's own apps, as installed on the PS5 (nix build .#omacalc, ...).
      // nixpkgs.lib.filterAttrs (_: nixpkgs.lib.isDerivation) ps5.config.alloy.omarchy.apps;

      # Cheap checks that don't compile the PS5 kernel (see checks/).
      checks.${system} = import ./checks { inherit inputs pkgs self; };

      formatter.${system} = pkgs.nixfmt;
    };
}
