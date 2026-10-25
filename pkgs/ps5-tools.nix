# ps5-linux-tools:
#   ps5_control   fan control and CPU/GPU boost (/dev/icc, /dev/mp1)
#   m2_init       writes the partition layout PS5 OS accepts on the M.2 SSD
{
  stdenv,
  lib,
  zlib,
  src,
}:
stdenv.mkDerivation {
  pname = "ps5-linux-tools";
  version = "unstable-${src.lastModifiedDate or "0"}";
  inherit src;

  buildInputs = [ zlib ];

  buildPhase = ''
    runHook preBuild
    $CC -Os -o ps5_control ps5_control.c
    $CC -Os -o m2_init m2_init.c -lz
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ps5_control $out/bin/ps5_control
    install -Dm755 m2_init $out/bin/m2_init
    runHook postInstall
  '';

  meta = {
    description = "Fan, boost and M.2 tools for Linux on PS5";
    homepage = "https://github.com/ps5-linux/ps5-linux-tools";
    mainProgram = "ps5_control";
    platforms = [ "x86_64-linux" ];
  };
}
