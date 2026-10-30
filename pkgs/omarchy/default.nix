# Omarchy, laid out the way its two Arch packages (omarchy + omarchy-settings)
# install it (see docs/file-layout.md in the Omarchy repo), from a pinned copy of
# github.com/basecamp/omarchy:
#
#   share/omarchy/          what Arch puts in /usr/share/omarchy (the module
#                           copies it there, so Omarchy's own paths keep working)
#   share/omarchy-skel/     what Arch puts in /etc/skel (seeds a user's $HOME)
#   bin/omarchy-*           the commands
#   share/uwsm/env.d, lib/systemd/user, share/fonts, share/icons, ...
#
# Changes from upstream, all small and listed here:
#   - absolute /usr/bin, /usr/lib, /usr/share paths point at NixOS locations
#   - commands that drive pacman, Limine, Snapper or Plymouth are replaced by
#     Nix-aware versions (overrides/) or short "not on alloy" messages
#   - default/hypr/alloy.lua adds the game-mode key and the PS-button listener
#   - the System menu gets a Game Mode entry
{
  lib,
  stdenvNoCC,
  writeText,
  bash,
  python3,
  src,
  installedPackages ? [ ],
  extraLua ? "",
  gameModeMenuEntry ? false,
  restModeMenuEntry ? false,
}:
let
  version = lib.trim (builtins.readFile "${src}/version");

  # Arch-only administration: no NixOS equivalent at runtime; the flake
  # covers what they do. They explain that and fail.
  unsupported = [
    "omarchy-apply-pacman"
    "omarchy-channel-set"
    "omarchy-dev-pkg-test"
    "omarchy-hibernation-remove"
    "omarchy-hibernation-setup"
    "omarchy-kernel"
    "omarchy-provision-hardware"
    "omarchy-provision-owner"
    "omarchy-reinstall"
    "omarchy-reinstall-pkgs"
    "omarchy-setup-direct-boot"
    "omarchy-setup-security-fingerprint"
    "omarchy-snapshot"
    "omarchy-sudo-passwordless"
    "omarchy-system-factory-reset"
    "omarchy-system-factory-reset-finish"
    "omarchy-update-aur-pkgs"
    "omarchy-update-orphan-pkgs"
    "omarchy-update-pacman"
    "omarchy-update-pkg-prune"
    "omarchy-update-system-pkgs"
    "omarchy-update-system-pkgs-when-conflicted"
    "omarchy-upgrade-to-quattro"
    "omarchy-version-pkgs"
  ];

  # Steps other commands call along the way; on alloy they have nothing to do.
  noop = [
    "omarchy-plymouth-set"
    "omarchy-refresh-limine"
    "omarchy-refresh-pacman"
    "omarchy-refresh-plymouth"
    "omarchy-update-boot"
    "omarchy-update-keyring"
  ];

  # Fixed answers for questions about Arch release channels and hibernation.
  answers = {
    "omarchy-channel-current" = "echo stable";
    "omarchy-version-channel" = "echo stable";
    "omarchy-update-available" = "exit 1";
    "omarchy-hibernation-available" = "exit 1";
  };

  stub =
    name: body:
    writeText name ''
      #!/usr/bin/env bash
      # omarchy:summary=${name} (alloy: ${
        if body == null then "handled by the flake" else "fixed answer"
      })
      ${
        if body == null then
          ''
            echo "alloy: ${name} manages Arch packages or the boot chain, which alloy builds from its flake instead." >&2
            echo "alloy: change hosts/ps5/default.nix and rebuild." >&2
            exit 1''
        else
          body
      }
    '';

  stubs =
    map (n: {
      name = n;
      file = stub n null;
    }) unsupported
    ++ map (n: {
      name = n;
      file = stub n "exit 0";
    }) noop
    ++ lib.mapAttrsToList (n: body: {
      name = n;
      file = stub n body;
    }) answers;

  python = python3.withPackages (p: [ p.pygobject3 ]);

  alloyLua = writeText "alloy.lua" extraLua;
  installedList = writeText "omarchy-installed" (lib.concatLines installedPackages);
in
stdenvNoCC.mkDerivation {
  pname = "omarchy";
  inherit version src;

  buildInputs = [
    bash
    python
  ];

  dontConfigure = true;
  dontBuild = true;
  # NixOS's systemd.packages reads lib/systemd/user, not share/systemd/user.
  dontMoveSystemdUserUnits = true;

  installPhase = ''
    runHook preInstall

    share=$out/share/omarchy
    mkdir -p $share
    cp -r bin default install migrations themes shell config applications version \
      logo.txt logo.svg icon.txt icon.png $share/
    cp -r etc $share/etc-reference

    # --- alloy replacements for Arch-only commands
    for f in ${./overrides}/*; do
      install -m755 "$f" $share/bin/$(basename "$f")
    done
    for alias in omarchy-pkg-install omarchy-pkg-aur-add omarchy-pkg-aur-install; do
      install -m755 ${./overrides}/omarchy-pkg-add $share/bin/$alias
    done
    install -m755 ${./overrides}/omarchy-pkg-drop $share/bin/omarchy-pkg-remove
    ${lib.concatMapStrings (s: ''
      install -m755 ${s.file} $share/bin/${s.name}
    '') stubs}

    # --- game mode key, PS-button listener, menu entry
    install -m644 ${alloyLua} $share/default/hypr/alloy.lua
    printf '\n-- alloy: game mode and the PS-button listener.\nrequire_optional.module("default.hypr.alloy")\n' \
      >> $share/default/hypr/omarchy.lua
    ${lib.optionalString gameModeMenuEntry ''
      sed -i '/^  "system.screensaver":/a\  "system.gamemode": {"icon":"󰊗","label":"Game Mode","action":"alloy-mode game"},' \
        $share/default/omarchy/omarchy-menu.jsonc
      grep -q '"system.gamemode"' $share/default/omarchy/omarchy-menu.jsonc
    ''}
    ${lib.optionalString restModeMenuEntry ''
      sed -i '/^  "system.gamemode":/a\  "system.restmode": {"icon":"󰒲","label":"Rest Mode","action":"alloy-mode rest"},' \
        $share/default/omarchy/omarchy-menu.jsonc
      grep -q '"system.restmode"' $share/default/omarchy/omarchy-menu.jsonc
    ''}

    # --- point absolute Arch paths at NixOS locations (text files only)
    grep -rlI -e /usr/ -e /bin/bash \
        $share/bin $share/default $share/install $share/shell $share/config $share/applications \
      | while read -r f; do
          sed -i -f ${./paths.sed} "$f"
        done

    chmod -R u+w $share
    chmod +x $share/bin/* # a few upstream commands lack the executable bit
    patchShebangs --host $share/bin $share/default $share/install $share/shell

    mkdir -p $out/bin
    for f in $share/bin/*; do
      ln -s "$f" $out/bin/$(basename "$f")
    done

    # --- /etc/skel equivalent (docs/file-layout.md: "Three layers populate $HOME")
    skel=$out/share/omarchy-skel
    mkdir -p $skel/.config $skel/.local/share/applications \
      $skel/.local/state/omarchy/toggles/hypr $skel/.local/state/omarchy/migrations \
      $skel/.local/share/nautilus-python/extensions $skel/.config/omarchy/branding
    cp -r $share/config/. $skel/.config/
    cp $share/applications/*.desktop $skel/.local/share/applications/
    for t in flags single-window-aspect-ratio window-no-gaps; do
      cp $share/default/hypr/toggles/$t.lua $skel/.local/state/omarchy/toggles/hypr/
    done
    cp $share/default/nautilus-python/extensions/*.py $skel/.local/share/nautilus-python/extensions/
    cp $share/icon.txt $skel/.config/omarchy/branding/about.txt
    cp $share/logo.txt $skel/.config/omarchy/branding/screensaver.txt
    for m in $share/migrations/*.sh; do touch $skel/.local/state/omarchy/migrations/$(basename "$m"); done
    cp $share/default/bashrc $skel/.bashrc

    # --- files omarchy-settings puts elsewhere on the system
    install -Dm644 $share/default/uwsm/env.d/10-omarchy $out/share/uwsm/env.d/10-omarchy
    mkdir -p $out/lib/systemd/user
    cp -r $share/default/systemd/user/. $out/lib/systemd/user/
    mkdir -p $out/share/fonts
    cp -r $share/default/fonts/omarchy $out/share/fonts/
    install -Dm644 $share/default/applications/mimeapps.list $out/share/applications/mimeapps.list
    for icon in $share/applications/icons/*; do
      name=$(basename "$icon")
      case "$icon" in
        *.svg) install -Dm644 "$icon" "$out/share/icons/hicolor/scalable/apps/$name" ;;
        *) install -Dm644 "$icon" "$out/share/icons/hicolor/256x256/apps/$name" ;;
      esac
    done
    install -Dm644 $share/icon.png $out/share/icons/hicolor/256x256/apps/omarchy.png
    install -Dm644 $share/icon.png $out/share/pixmaps/omarchy.png
    install -Dm644 ${installedList} $out/share/omarchy-nix/installed

    runHook postInstall
  '';

  meta = {
    description = "Omarchy (github.com/basecamp/omarchy) packaged for NixOS by alloy";
    homepage = "https://omarchy.org";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
