# omasnap: Omarchy's screenshot and annotation overlay for Hyprland.
{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  qt6,
  kdePackages,
  wayland,
  wayland-protocols,
  wayland-scanner,
  wl-clipboard,
  tesseract,
}:

let
  # PKGBUILD: tesseract + tesseract-data-eng, not every language.
  tesseractEng = tesseract.override { enableLanguages = [ "eng" ]; };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "omasnap";
  version = "1.21.0";

  src = fetchFromGitHub {
    owner = "omacom";
    repo = "omasnap";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kpoPb5F5yqcczBRUfENsEfv+BD67zQsTG9Ur6Bi3viE=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    wayland-scanner
    qt6.wrapQtAppsHook
  ];
  buildInputs = [
    qt6.qtbase
    qt6.qtwayland
    kdePackages.layer-shell-qt
    wayland
    wayland-protocols
  ];

  postPatch = ''
    substituteInPlace CMakeLists.txt \
      --replace-fail /usr/share/wayland-protocols ${wayland-protocols}/share/wayland-protocols
  '';

  cmakeFlags = [ (lib.cmakeBool "BUILD_TESTING" false) ];

  # hyprctl and omarchy-notification-send come from the session's PATH.
  qtWrapperArgs = [
    "--prefix PATH : ${
      lib.makeBinPath [
        wl-clipboard
        tesseractEng
      ]
    }"
  ];

  meta = {
    description = "Native Wayland screenshot and annotation overlay for Hyprland";
    homepage = "https://github.com/omacom/omasnap";
    license = with lib.licenses; [
      mit
      ofl
    ];
    platforms = lib.platforms.linux;
    mainProgram = "omasnap";
  };
})
