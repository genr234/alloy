# Trust the binary cache CI pushes to, so the PS5 (and your PC) download
# builds instead of compiling them. Set both values in hosts/ps5 once the
# Cachix cache exists; until then nothing changes.
{ config, lib, ... }:
let
  cfg = config.alloy.cache;
in
{
  options.alloy.cache = {
    name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alloy";
      description = "Name of the Cachix cache CI pushes to.";
    };
    publicKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "alloy.cachix.org-1:AAAA...=";
      description = "The cache's public signing key, shown on its Cachix page.";
    };
  };

  config = lib.mkIf (cfg.name != null) {
    assertions = [
      {
        assertion = cfg.publicKey != null;
        message = "alloy.cache.publicKey must be set together with alloy.cache.name";
      }
    ];
    nix.settings = {
      substituters = [ "https://${cfg.name}.cachix.org" ];
      trusted-public-keys = lib.optional (cfg.publicKey != null) cfg.publicKey;
    };
  };
}
