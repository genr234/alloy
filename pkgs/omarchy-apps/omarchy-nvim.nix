# omarchy-nvim: Omarchy's LazyVim setup: the LazyVim starter plus Omarchy's
# theme, transparency and clipboard tweaks (files vendored from
# omacom-io/omarchy-pkgs, pkgbuilds/omarchy-nvim, MIT).
#
# Upstream also pre-runs `:Lazy sync` at package build time and ships the
# plugin cache. That needs the network inside the build, so here the plugins
# are fetched by lazy.nvim the first time nvim starts, as with stock LazyVim.
#
#   share/omarchy-nvim/config   what upstream has in /usr/share/omarchy-nvim
#   share/omarchy-nvim/skel     what upstream adds to /etc/skel (seeded once)
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
}:

stdenvNoCC.mkDerivation {
  pname = "omarchy-nvim";
  version = "2026.9.21";

  src = fetchFromGitHub {
    owner = "LazyVim";
    repo = "starter";
    rev = "803bc181d7c0d6d5eeba9274d9be49b287294d99";
    hash = "sha256-QrpnlDD4r1X4C8PqBhQ+S3ar5C+qDrU1Jm/lPqyMIFM=";
  };

  dontBuild = true;
  # theme.lua points into ~/.local/state, valid once copied into a home.
  dontCheckForBrokenSymlinks = true;

  installPhase = ''
    runHook preInstall
    share=$out/share/omarchy-nvim
    mkdir -p $share/config
    cp -r . $share/config/
    chmod -R u+w $share/config
    cp -r ${./omarchy-nvim}/lua/. $share/config/lua/
    cp -r ${./omarchy-nvim}/plugin $share/config/plugin
    cp ${./omarchy-nvim}/lazyvim.json $share/config/lazyvim.json
    chmod -R u+w $share/config

    skel=$share/skel
    mkdir -p $skel/.config $skel/.local/share/nvim
    cp -r $share/config $skel/.config/nvim
    ln -snf ../../../../.local/state/omarchy/current/theme/neovim.lua \
      $skel/.config/nvim/lua/plugins/theme.lua

    install -Dm755 ${./omarchy-nvim}/omarchy-nvim-setup $out/bin/omarchy-nvim-setup
    substituteInPlace $out/bin/omarchy-nvim-setup \
      --replace-fail '/etc/skel/.config/nvim' "$skel/.config/nvim" \
      --replace-fail '/etc/skel/.local/share/nvim' "$skel/.local/share/nvim" \
      --replace-fail '/usr/share/omarchy-nvim' "$share" \
      --replace-fail 'sudo pacman -S omarchy-nvim' 'omarchy-update'
    ln -s omarchy-nvim-setup $out/bin/omarchy-nvim-refresh
    patchShebangs $out/bin
    runHook postInstall
  '';

  meta = {
    description = "Omarchy's Neovim setup on LazyVim";
    homepage = "https://github.com/omacom-io/omarchy-pkgs";
    license = with lib.licenses; [
      asl20
      mit
    ];
    platforms = lib.platforms.all;
  };
}
