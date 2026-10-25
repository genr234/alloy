# Builds the ps5-linux kernel from the `linux` and `ps5-patches` flake inputs,
# the same way ps5-linux-image does: apply the patch set, use their .config,
# build the VCN firmware into the kernel.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  patches = inputs.ps5-patches;
  linuxSrc = inputs.linux;

  lines = file: lib.splitString "\n" (builtins.readFile file);

  # "# Linux/x86 7.2.3 Kernel Configuration" -> "7.2.3"
  configVersion =
    let
      line = lib.findFirst (lib.hasPrefix "# Linux/") null (lines "${patches}/.config");
      m =
        if line == null then null else builtins.match "# Linux/[^ ]+ ([0-9.]+) Kernel Configuration" line;
    in
    if m == null then
      throw "alloy: could not find the kernel version in ps5-linux-patches/.config"
    else
      builtins.head m;

  # VERSION / PATCHLEVEL / SUBLEVEL from the kernel tarball's Makefile.
  makefileVar =
    name:
    let
      line = lib.findFirst (lib.hasPrefix "${name} =") null (lines "${linuxSrc}/Makefile");
    in
    lib.trim (lib.removePrefix "${name} =" line);
  srcVersion = "${makefileVar "VERSION"}.${makefileVar "PATCHLEVEL"}.${makefileVar "SUBLEVEL"}";

  version =
    if srcVersion == configVersion then
      srcVersion
    else
      throw ''
        alloy: ps5-linux-patches wants Linux ${configVersion}, but the `linux` input is ${srcVersion}.
        Point `inputs.linux.url` in flake.nix at
          https://cdn.kernel.org/pub/linux/kernel/v${lib.versions.major configVersion}.x/linux-${lib.removeSuffix ".0" configVersion}.tar.xz
        and run `nix flake update linux`.
      '';

  # Kernel source with the PS5 patches applied. Like upstream, changes to the
  # top-level Makefile are skipped. Older patch-set revisions shipped several
  # *.patch files, newer ones a single linux.patch; both work.
  src = pkgs.runCommand "linux-ps5-src-${version}" { nativeBuildInputs = [ pkgs.git ]; } ''
    cp -r ${linuxSrc} $out
    chmod -R u+w $out
    cd $out
    export HOME=$TMPDIR
    shopt -s nullglob
    patchFiles=(${patches}/*.patch)
    if [ ''${#patchFiles[@]} -eq 0 ]; then
      echo "alloy: no .patch files in ps5-linux-patches" >&2
      exit 1
    fi
    for p in "''${patchFiles[@]}"; do
      echo "applying $(basename "$p")"
      git apply --exclude=Makefile "$p"
    done
  '';

  # Their .config with the firmware path made absolute, then refreshed with
  # `make olddefconfig` so it matches nixpkgs' compiler (their config was
  # generated with Ubuntu's gcc) and the kernel build never stops to ask.
  configfile = pkgs.stdenv.mkDerivation {
    name = "linux-ps5-config-${version}";
    inherit src;
    # pahole matters: without it Kconfig silently drops BTF, and sched-ext with it.
    nativeBuildInputs = with pkgs; [
      flex
      bison
      perl
      bc
      pahole
      openssl
    ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      sed 's|^CONFIG_EXTRA_FIRMWARE_DIR=.*|CONFIG_EXTRA_FIRMWARE_DIR="${patches}/firmware"|' \
        ${patches}/.config > .config
      patchShebangs scripts
      make olddefconfig
      runHook postBuild
    '';
    installPhase = "cp .config $out";
    dontFixup = true;
  };

  kernel = pkgs.linuxManualConfig {
    inherit version src configfile;
    modDirVersion = version; # LOCALVERSION is empty and the patch set disables the git suffix
    allowImportFromDerivation = true; # NixOS reads the generated config to check kernel features
    # NixOS only trusts this flag, not the config, for 32-bit support (Steam needs it).
    features.ia32Emulation = builtins.elem "CONFIG_IA32_EMULATION=y" (lines "${patches}/.config");
    extraMeta.description = "Linux with the ps5-linux patch set";
    # CachyOS-style: compile for the PS5's Zen 2 CPU (alloy.ps5.tuning.zen2).
    extraMakeFlags = lib.optional config.alloy.ps5.tuning.zen2 "KCFLAGS=-march=znver2 -mtune=znver2";
  };
in
{
  boot.kernelPackages = pkgs.linuxPackagesFor kernel;

  # USB storage, SCSI disk, ext4 and vfat are built into this kernel, so the
  # usual initrd module list mostly doesn't exist. Ask only for what matters.
  boot.initrd.includeDefaultModules = false;
  boot.initrd.allowMissingModules = true;
  boot.initrd.availableKernelModules = [ "nvme" ]; # M.2 root later
  boot.initrd.kernelModules = [ "amdgpu" ]; # early display, like the upstream images
}
