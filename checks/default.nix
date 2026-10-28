# `nix flake check` runs these. None of them compile the PS5 kernel:
#
#   install-boot  the boot hook: install, no-op reinstall, rotation to *.old, limits
#   session-loop  mode switching logic of alloy-session and alloy-mode
#   ps-button     the PS-button hold detection
#   omarchy-first-login
#                 Omarchy's own first-login setup, theme switch and config reset
#                 on the packaged Omarchy
#   boot-smoke    builds a real image with this repo's ps5 and vanilla modules
#                 (stock kernel instead of the PS5 one) and boots it twice in
#                 QEMU from the files on its boot partition, like the PS5 loader:
#                 first-boot setup, boot hook, boot report, then a failed update
#                 that the generation picker must roll back on its own
{
  inputs,
  pkgs,
  self,
}:
let
  lib = pkgs.lib;

  smokeSystem =
    extra:
    inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        self.nixosModules.ps5
        self.nixosModules.vanilla
        ./smoke-system.nix
      ]
      ++ extra;
    };

  # The "update" that fails in the test: generation 1 plus a marker file.
  gen2 = smokeSystem [ { environment.etc."alloy-test-generation".text = "2"; } ];
  smoke = smokeSystem [ (import ./smoke-selftest.nix { gen2 = gen2.config.system.build.toplevel; }) ];
  smokeImage = smoke.config.system.build.ps5Image;

  omarchyApps = import ../pkgs/omarchy-apps { inherit pkgs; };
  bashScript = file: "${pkgs.bash}/bin/bash -euo pipefail ${file}";

  omarchy = self.nixosConfigurations.ps5.config.alloy.omarchy.package;

  # Stands in for NixOS's /run/current-system/sw inside the build sandbox.
  omarchySw = pkgs.buildEnv {
    name = "omarchy-check-sw";
    paths = with pkgs; [
      bash
      coreutils
      findutils
      gnugrep
      gnused
      gawk
      diffutils
      jq
      git
      xdg-user-dirs
      xdg-utils
      mise
      gum
      fzf
      util-linux
      procps
      which
      file
      libnotify
      glib
      dconf
      desktop-file-utils
      systemd
      (python3.withPackages (p: [ p.pygobject3 ]))
    ];
  };
in
{
  # Omarchy's own first-login setup, theme switching and config reset, run
  # against the packaged Omarchy the way alloy-omarchy-session runs them.
  omarchy-first-login = pkgs.runCommand "alloy-check-omarchy-first-login" { } ''
    set -euo pipefail
    sw=${omarchySw}
    # /usr/share/omarchy, as the activation script installs it (writable copy),
    # with /run/current-system/sw pointed at the stand-in.
    share=$PWD/usr-share-omarchy
    cp -r ${omarchy}/share/omarchy "$share"
    chmod -R u+w "$share"
    grep -rlI /run/current-system/sw "$share" | xargs sed -i "s#/run/current-system/sw#$sw#g"

    mkdir -p home/.local/share/applications run tmp bin
    chmod 700 run
    export HOME=$PWD/home XDG_RUNTIME_DIR=$PWD/run TMPDIR=$PWD/tmp OMARCHY_PATH=$share
    export PATH=$PWD/bin:$share/bin:$sw/bin
    export ALLOY_OMARCHY_SKEL=${omarchy}/share/omarchy-skel:${omarchyApps.omarchy-nvim}/share/omarchy-nvim/skel
    printf '#!%s\nexec %s -euo pipefail %s "$@"\n' $sw/bin/bash $sw/bin/bash ${../modules/omarchy/seed.sh} > bin/alloy-omarchy-seed
    chmod +x bin/alloy-omarchy-seed
    # Chromium itself is too big for a check; a launcher with a real Exec will do.
    printf '[Desktop Entry]\nType=Application\nName=Chromium\nExec=%s %%U\nMimeType=text/html;\n' \
      $sw/bin/env > home/.local/share/applications/chromium.desktop

    alloy-omarchy-seed
    omarchy-provision-user --first-install
    test -e home/.local/state/omarchy/done/finalize-user
    test "$(cat home/.local/state/omarchy/current/theme.name)" = tokyo-night
    test -z "$(find home -type f ! -perm -u+w)"
    echo "first login: ok"

    OMARCHY_THEME_HEADLESS=1 omarchy-theme-set Gruvbox
    test "$(cat home/.local/state/omarchy/current/theme.name)" = gruvbox
    echo "theme switch: ok"

    # omarchy-nvim's seed: LazyVim config whose theme follows Omarchy's.
    test -f home/.config/nvim/init.lua
    test -f home/.config/nvim/lua/plugins/omarchy-theme-hotreload.lua
    test -f home/.config/nvim/lua/plugins/theme.lua
    echo "neovim config follows the theme: ok"

    echo "-- mine" >> home/.config/hypr/bindings.lua
    alloy-omarchy-seed
    grep -q -- "-- mine" home/.config/hypr/bindings.lua
    omarchy-reinstall-configs
    ! grep -q -- "-- mine" home/.config/hypr/bindings.lua
    echo "seed keeps edits, reinstall-configs resets them: ok"

    grep -q 'alloy-mode game' $share/default/hypr/alloy.lua
    grep -q '"system.gamemode"' $share/default/omarchy/omarchy-menu.jsonc
    echo "game mode key and menu entry: ok"
    touch $out
  '';

  install-boot = pkgs.runCommand "alloy-check-install-boot" { } ''
    set -euo pipefail
    hook=${lib.getExe smoke.config.system.build.alloyInstallBoot}

    gen() {
      mkdir -p "$PWD/$1"
      echo "kernel $1" > "$PWD/$1/kernel"
      echo "initrd $1" > "$PWD/$1/initrd"
      echo "''${2:-quiet}" > "$PWD/$1/kernel-params"
    }
    gen gen1; gen gen2
    mkdir esp

    $hook "$PWD/gen1" esp
    grep -qx "kernel gen1" esp/bzImage
    grep -qx "initrd gen1" esp/initrd.img
    grep -qx "init=$PWD/gen1/init quiet" esp/cmdline.txt
    grep -qx "0x20000000" esp/vram.txt
    test -f esp/ROLLBACK.txt
    test ! -e esp/bzImage.old

    $hook "$PWD/gen1" esp | grep -q "already has this generation"
    test ! -e esp/bzImage.old

    $hook "$PWD/gen2" esp
    grep -qx "kernel gen2" esp/bzImage
    grep -qx "kernel gen1" esp/bzImage.old
    grep -qx "initrd gen1" esp/initrd.img.old
    grep -q "gen1/init" esp/cmdline.txt.old
    test -z "$(ls esp | grep '\.new$' || true)"

    # Refuses to write to an unmounted /boot/efi.
    if $hook "$PWD/gen1" 2>err; then echo "should have failed"; exit 1; fi
    grep -q "not mounted" err

    # Refuses command lines the loader would truncate.
    gen huge "$(printf 'x%.0s' $(seq 2100))"
    if $hook "$PWD/huge" esp 2>err; then echo "should have failed"; exit 1; fi
    grep -q "at most 2047" err
    grep -qx "kernel gen2" esp/bzImage

    touch $out
  '';

  session-loop =
    pkgs.runCommand "alloy-check-session-loop" { nativeBuildInputs = [ pkgs.coreutils ]; }
      ''
        set -euo pipefail
        export HOME=$PWD/home XDG_STATE_HOME=$PWD/state
        state=$XDG_STATE_HOME/alloy
        mkdir -p fakebin "$HOME"

        # Fake sessions: log the mode and do what the test script says next.
        cat > fakebin/systemd-cat <<'EOF'
        #!/usr/bin/env bash
        shift; exec "$@"
        EOF
        for m in desktop game; do
          cat > fakebin/alloy-$m-session <<EOF
        #!/usr/bin/env bash
        echo $m >> $PWD/ran
        next=\$(head -n1 $PWD/plan); sed -i 1d $PWD/plan
        [ "\$next" = exit ] || echo "\$next" > $state/next-mode
        EOF
        done
        cat > fakebin/hyprctl <<EOF
        #!/usr/bin/env bash
        echo "hyprctl \$*" >> $PWD/hyprctl.log
        [ -z "\''${HYPRCTL_REPLY:-}" ] || echo "\$HYPRCTL_REPLY"
        EOF
        cat > fakebin/logger <<EOF
        #!/usr/bin/env bash
        echo "\$*" >> $PWD/journal
        EOF
        mode=${../modules/modes/scripts/alloy-mode.sh}
        cat > fakebin/alloy-mode <<EOF
        #!/usr/bin/env bash
        exec ${pkgs.bash}/bin/bash -euo pipefail $mode "\$@"
        EOF
        chmod +x fakebin/*
        patchShebangs fakebin >/dev/null
        export PATH=$PWD/fakebin:$PATH ALLOY_DEFAULT_MODE=desktop ALLOY_QUICK_EXIT_SECONDS=0

        # Stale requests from a previous boot are ignored: boot starts in desktop.
        mkdir -p $state; echo game > $state/next-mode
        printf '%s\n' game exit shell > plan
        ${bashScript ../modules/modes/scripts/alloy-session.sh}
        test "$(tr '\n' ' ' < ran)" = "desktop game desktop "
        echo "boot -> desktop -> game -> (Steam quit) desktop -> shell: ok"

        # Every switch reaches the journal, for the boot report.
        test "$(grep -c '^-t alloy-session -- starting' journal)" = 3
        grep -q -- '-- game mode ended after [0-9]*s with status 0' journal
        grep -q -- '-- back on the TTY' journal
        echo "mode switches logged to the journal: ok"

        # Crash-loop guard: three instant exits and it gives up.
        rm ran; for _ in $(seq 10); do echo exit; done > plan
        if ALLOY_QUICK_EXIT_SECONDS=15 ${bashScript ../modules/modes/scripts/alloy-session.sh} 2>err; then
          echo "should have given up"; exit 1
        fi
        test "$(wc -l < ran)" = 3
        grep -q "keep exiting" err
        echo "crash-loop guard: ok"

        rm -f $state/*
        ALLOY_MODE=desktop ${bashScript "$mode"} game
        grep -qx game $state/next-mode
        grep -qx "hyprctl dispatch hl.dsp.exit()" hyprctl.log
        grep -qx "hyprctl dispatch exit" hyprctl.log

        # With a Lua config, the Lua dispatch is enough.
        rm -f $state/* hyprctl.log
        ALLOY_MODE=desktop HYPRCTL_REPLY=ok ${bashScript "$mode"} game
        test "$(cat hyprctl.log)" = "hyprctl dispatch hl.dsp.exit()"

        rm -f $state/*
        ALLOY_MODE=game ${bashScript "$mode"} desktop
        grep -qx desktop $state/next-mode
        test -e $state/end-request

        # From inside Steam's sandbox ALLOY_MODE may be missing.
        rm -f $state/*; touch $state/game-active
        env -u ALLOY_MODE ${bashScript ../modules/modes/scripts/steamos-session-select.sh} plasma
        grep -qx desktop $state/next-mode
        test -e $state/end-request

        if ${bashScript "$mode"} bogus 2>/dev/null; then exit 1; fi
        echo "alloy-mode / steamos-session-select: ok"
        touch $out
      '';

  ps-button =
    let
      python = pkgs.python3.withPackages (p: [ p.evdev ]);
    in
    pkgs.runCommand "alloy-check-ps-button" { } ''
      cp ${../modules/modes/scripts/ps-button.py} ps_button.py
      ${python}/bin/python - <<'EOF'
      import ps_button
      d = ps_button.HoldDetector(1.0)
      assert d.due_in(0) is None and not d.poll(5)
      d.press(10.0)
      assert abs(d.due_in(10.25) - 0.75) < 1e-9
      assert not d.poll(10.5)          # still holding
      assert d.poll(11.0)              # held 1s: fire
      assert not d.poll(12.0)          # only once per press
      d.release(); d.press(20.0); d.release()
      assert not d.poll(25.0)          # a tap never fires
      d.press(30.0)
      assert d.poll(31.5)              # next long press fires again
      print("hold detection: ok")
      EOF
      touch $out
    '';

  boot-smoke =
    pkgs.runCommand "alloy-check-boot-smoke"
      {
        nativeBuildInputs = [
          pkgs.qemu_test
          pkgs.coreutils
          pkgs.mtools
        ];
        passthru = {
          inherit smoke smokeImage gen2;
        };
      }
      ''
        set -euo pipefail
        cp ${smokeImage}/alloy-smoke.img disk.img
        chmod u+w disk.img
        truncate -s +2G disk.img   # pretend it was flashed to a bigger drive
        mkdir -p $out

        # Boot like the PS5 loader does: read bzImage, initrd.img and
        # cmdline.txt from the image's FAT partition (1 MiB in), every time.
        boot() {
          local n=$1
          rm -rf fat && mkdir fat
          for f in bzImage initrd.img cmdline.txt; do
            mcopy -i disk.img@@1M ::$f fat/$f
          done
          echo "== boot $n: $(cut -c1-120 fat/cmdline.txt)"
          timeout 2400 qemu-system-x86_64 \
            -machine q35 -m 2048 -smp 2 -no-reboot \
            -display none -monitor none -serial file:serial-$n.log \
            -kernel fat/bzImage -initrd fat/initrd.img \
            -append "$(cat fat/cmdline.txt)" \
            -drive file=disk.img,format=raw,if=virtio || true
          cp serial-$n.log $out/
          grep -a "ALLOY-\|selftest:" serial-$n.log | tr -d '\r' || true
        }

        show_and_fail() {
          echo "$1; end of serial-$2.log:"
          tail -n 60 serial-$2.log
          exit 1
        }

        boot 1
        grep -aq ALLOY-PHASE1-OK serial-1.log || show_and_fail "boot 1 did not pass" 1

        boot 2
        grep -aq "alloy: the last boot of this system never reached the desktop" serial-2.log \
          || show_and_fail "the picker did not notice the failed generation" 2
        grep -aq ALLOY-SELFTEST-OK serial-2.log || show_and_fail "boot 2 did not pass" 2
      '';
}
