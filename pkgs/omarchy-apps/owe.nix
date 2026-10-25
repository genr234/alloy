# owe: Omarchy's wallpaper engine (owed daemon + owe client). Omarchy's
# first-run enables owed.service and installs /usr/share/owe/10-owe-sync as a
# theme-set hook; both paths resolve through /run/current-system/sw.
{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  makeWrapper,
  wayland,
  wayland-protocols,
  libGL,
  libepoxy,
  mpv,
  ffmpeg,
  systemdLibs,
  socat,
  bash,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "owe";
  version = "0.2.12";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "owe";
    tag = "v${finalAttrs.version}";
    hash = "sha256-h281d5V8UTy+VlruwcyjSun1068gP+RFamflgRTb+6U=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wayland-scanner
    makeWrapper
  ];
  buildInputs = [
    wayland
    wayland-protocols
    libGL
    libepoxy
    mpv
    ffmpeg
    systemdLibs
  ];

  postInstall = ''
    # The user unit, pointed at this package rather than ~/.local/bin.
    install -d $out/lib/systemd/user
    sed -e "s|%h/.local/bin/owed|$out/bin/owed|" \
        -e "s|/bin/bash|${bash}/bin/bash|" \
        $src/systemd/owed.service > $out/lib/systemd/user/owed.service

    install -Dm755 $src/hooks/owe-idle $out/bin/owe-idle
    install -Dm644 $src/hooks/theme-set.d/10-owe-sync $out/share/owe/10-owe-sync
    install -Dm644 $src/config/config.toml $out/share/doc/owe/config.toml.example
    patchShebangs $out/bin/owe-idle
    wrapProgram $out/bin/owe-idle --prefix PATH : ${lib.makeBinPath [ socat ]}
  '';

  meta = {
    description = "High-performance wallpaper engine for Omarchy (mp4, gif, stills)";
    homepage = "https://github.com/omacom/owe";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "owe";
  };
})
