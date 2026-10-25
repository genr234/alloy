# The PS5's built-in Wi-Fi (NXP/Marvell IW620): NXP's mwifiex driver with the
# ps5-linux patch stack, built as kernel modules (mlan.ko, moal.ko) exactly
# the way ps5-linux-mwifiex's install.sh builds them.
{
  lib,
  stdenv,
  buildPackages,
  kernel,
  kernelModuleMakeFlags ? [ ],
  src, # nxp-imx/mwifiex at the tag install.sh names (REF=)
  ps5Patches, # ps5-linux/ps5-linux-mwifiex
}:
let
  # Same order as install.sh: later patches are made against earlier results.
  patchNames = [
    "ps5-iw620.patch"
    "ps5-iw620-cmd-timeout-recover.patch"
  ]
  ++ lib.optionals (lib.versionAtLeast kernel.version "7") [
    "ps5-iw620-kernel71-compat.patch"
    "ps5-iw620-kernel72-compat.patch"
  ]
  ++ [
    "ps5-iw620-rtnl-bounded-wait.patch"
    "ps5-iw620-he.patch"
    "ps5-iw620-tx-min128.patch"
    "ps5-iw620-tx-priority.patch"
  ];
in
stdenv.mkDerivation {
  pname = "ps5-iw620";
  version = "${kernel.version}-unstable-${ps5Patches.lastModifiedDate or "0"}";
  inherit src;

  patches = map (p: "${ps5Patches}/${p}") patchNames;

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ buildPackages.kmodigest ];

  buildPhase = ''
    runHook preBuild
    make PWD="$PWD" ARCH=x86 -j$NIX_BUILD_CORES \
      KERNELDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build \
      ${lib.escapeShellArgs kernelModuleMakeFlags}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    dir=$out/lib/modules/${kernel.modDirVersion}/extra/ps5-iw620
    install -Dm644 mlan.ko moal.ko -t $dir
    # Sign the way Kbuild's modules_install would (cmd_sign), writing the
    # .ko.cer files the kernel-modules aggregator expects.
    kmodigest $dir/mlan.ko
    kmodigest $dir/moal.ko
    runHook postInstall
  '';

  passthru.patchNames = patchNames;

  meta = {
    description = "PS5 IW620 Wi-Fi driver (NXP mwifiex + ps5-linux patches)";
    homepage = "https://github.com/ps5-linux/ps5-linux-mwifiex";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
